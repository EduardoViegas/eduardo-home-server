# Docker compose YAML reference
alias dcp='docker-compose -f ~/docker-compose/docker-compose.yaml'

# Move files from Nextcloud's Plex Folder to Plex Movies Folder
alias mtp ='mv /mnt/storage/data/nextcloud/data/eduardoviegas/files/Filmes\ -\ Plex/* /mnt/storage/data/media/movies/'

# Prints the IP, network and listening ports for each docker container
alias dcips=$'docker inspect -f \'{{.Name}}-{{range  $k, $v := .NetworkSettings.Networks}}{{$k}}-{{.IPAddress}} {{end}}-{{range $k, $v := .NetworkSettings.Ports}}{{ if not $v }}{{$k}} {{end}}{{end}} -{{range $k, $v := .NetworkSettings.Ports}}{{ if $v }}{{$k}} => {{range . }}{{ .HostIp}}:{{.HostPort}}{{end}}{{end}} {{end}}\' $(docker ps -aq) | column -t -s-'
