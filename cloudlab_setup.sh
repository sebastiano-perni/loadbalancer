#!/bin/bash
# cloudlab_setup.sh

# Update and install dependencies
sudo apt-get update
sudo apt-get install -y wget curl git bc

# Install Go 1.24.2
wget https://go.dev/dl/go1.24.2.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.24.2.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile
source /etc/profile

# Install hey for load generation
sudo /usr/local/go/bin/go install github.com/rakyll/hey@latest
echo 'export PATH=$PATH:/root/go/bin' | sudo tee -a /etc/profile

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Build the binaries
cd /local/repository || exit
/usr/local/go/bin/go build -o lb-binary ./cmd/server
cd backend || exit
/usr/local/go/bin/go build -o backend-binary main.go