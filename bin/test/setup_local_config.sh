DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
BIN_DIR=${BIN_DIR:-$(cd "${0%/*}"&&pwd)}
cd $BIN_DIR

source $BIN_DIR/../util/util.sh

build_contracts $BIN_DIR/../../

# set SETH enviroment variable
source $BIN_DIR/local_env.sh

# Defaults
test -z "$CURRENCY_SYMBOL" && CURRENCY_SYMBOL="DAI"
test -z "$CURRENCY_NAME" && CURRENCY_NAME="DAI Stablecoin"
test -z "$CURRENCY_VERSION" && CURRENCY_VERSION="a"
test -z "$CURRENCY_CHAINID" && CURRENCY_CHAINID=1

# Deploy Default Currency
TINLAKE_CURRENCY=$(seth send --create $BIN_DIR/../../out/SimpleToken.bin 'SimpleToken(string memory,string memory,string memory, uint)' "$CURRENCY_SYMBOL" "$CURRENCY_NAME" "$CURRENCY_VERSION" $(seth --to-uint256 $CURRENCY_CHAINID))

message test currency contract deployed
CONFIG_FILE=$1
[ -z "$1" ] && CONFIG_FILE="$BIN_DIR/../config_$(seth chain).json"

touch $CONFIG_FILE


addValuesToFile $CONFIG_FILE <<EOF
{
    "ETH_RPC_URL" :"$ETH_RPC_URL",
    "ETH_FROM" :"$ETH_FROM",
    "ETH_GAS" :"$ETH_GAS",
    "ETH_KEYSTORE" :"$ETH_KEYSTORE",
    "ETH_PASSWORD" :"$ETH_PASSWORD",
    "TINLAKE_CURRENCY": "$TINLAKE_CURRENCY"
}
EOF
message config file created

msg Path: $(realpath $CONFIG_FILE)

