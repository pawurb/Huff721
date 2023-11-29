fswatch -or src test -e "src/__TEMP__*" | xargs -n1 -I{} forge test -vv --mp $1
