#!/bin/bash

genesis_repository="pk910/test-testnet-repo"
testnet_dir=/var/lib/ethereum/testnet
el_datadir=/var/lib/goethereum
cl_datadir=/var/lib/lighthouse
cl_port=5052


start_clients() {
  # start EL / CL clients
  echo "start clients"
  sudo systemctl start geth
  sudo systemctl start lighthousebeacon
  sudo systemctl start lighthousevalidator
}

stop_clients() {
  # stop EL / CL clients
  echo "stop clients"
  sudo systemctl stop geth
  sudo systemctl stop lighthousebeacon
  sudo systemctl stop lighthousevalidator
}

clear_datadirs() {
  if [ -d $el_datadir/geth ]; then
    geth_nodekey=$(sudo cat $el_datadir/geth/nodekey)
    sudo rm -rf $el_datadir/geth
    sudo mkdir $el_datadir/geth
    sudo echo $geth_nodekey > $el_datadir/geth/nodekey
    sudo chown -R goeth:goeth /var/lib/goethereum
  fi

  sudo rm -rf $cl_datadir/beacon
  sudo rm -rf $cl_datadir/validators/slashing_protection.sqlite
}

setup_genesis() {
  # init el genesis
  sudo -u goeth geth init --datadir $el_datadir $testnet_dir/genesis.json
}



get_github_release() {
  curl --silent "https://api.github.com/repos/$1/releases/latest" |
    grep '"tag_name":' |
    sed -E 's/.*"([^"]+)".*/\1/' |
    head -n 1
  
}

download_genesis_release() {
  genesis_release=$1

  # remove old genesis
  if [ -d $testnet_dir ]; then
    rm -rf $testnet_dir/*
  else
    mkdir -p $testnet_dir
  fi

  # get latest genesis
  wget -qO- https://github.com/$genesis_repository/releases/download/$genesis_release/testnet-all.tar.gz | tar xvz -C $testnet_dir
  sudo chmod -R +r $testnet_dir
}

reset_testnet() {
  stop_clients
  clear_datadirs
  download_genesis_release $1
  setup_genesis
  start_clients
}

check_testnet() {
  current_time=$(date +%s)
  genesis_time=$(curl -s http://localhost:$cl_port/eth/v1/beacon/genesis | sed 's/.*"genesis_time":"\{0,1\}\([^,"]*\)"\{0,1\}.*/\1/')
  if ! [ $genesis_time -gt 0 ]; then
    echo "could not get genesis time from beacon node"
    return 0
  fi

  if ! [ -f $testnet_dir/retention.vars ]; then
    echo "could not find retention.vars"
    return 0
  fi
  source $testnet_dir/retention.vars

  testnet_timeout=$(expr $genesis_time + $GENESIS_RESET_INTERVAL - 300)
  echo "genesis timeout: $(expr $testnet_timeout - $current_time) sec"
  if [ $testnet_timeout -le $current_time ]; then
    genesis_release=$(get_github_release $genesis_repository)
    if ! [ $ITERATION_RELEASE ]; then
      ITERATION_RELEASE=$CHAIN_ID
    fi
    if [ $genesis_release = $ITERATION_RELEASE ]; then
      echo "could not find new genesis release (release: $genesis_release)"
      return 0
    fi
    
    reset_testnet $genesis_release
  fi
}

main() {
  if ! [ -f $testnet_dir/genesis.json ]; then
    reset_testnet $(get_github_release $genesis_repository)
  else
    check_testnet
  fi

}

main
