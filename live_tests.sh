fswatch -or src test -e "src/__TEMP__*" | xargs -n1 -I{} sh -c "./build_bytecode.sh && forge test -vv --mp $1"
