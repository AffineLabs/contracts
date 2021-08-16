starttmux() {
    if [ -z "$HOSTS" ]; then
       echo -n "Please provide of list of hosts separated by spaces [ENTER]: "
       read HOSTS
    fi

    local hosts=( $HOSTS )


    tmux new-window "docker exec -i -t ${hosts[0]} bash"
    unset hosts[0];
    for i in "${hosts[@]}"; do
        tmux split-window -h  "docker exec -i -t $i sh"
        tmux select-layout tiled > /dev/null
    done
    tmux select-pane -t 0
    tmux set-window-option synchronize-panes on > /dev/null

}

# HOSTS=${HOSTS:=$*}
HOSTS=${HOSTS:=bor0 }

starttmux