#!/usr/bin/env bash

# Using a python virtual environnement at $HOME/pyenv insted of $HOME/miniconda
# replace all "conda install" by "pip3 install"

creature=$1
hostname=$2
branch=${3:-"master"}

snap_version="4.1.0.4"
puppet_master_branch="1.0.1"

export PATH="$HOME/pyenv/bin:$PATH"

# activate the python virtual env for all the script
source $HOME/pyenv/bin/activate

print_env()
{
    env
}

install_poppy_libraries()
{
    pip install "$creature"

    if [ -z "${POPPY_ROOT+x}" ]; then
        export POPPY_ROOT="$HOME/dev"
        echo "export POPPY_ROOT=$HOME/dev" >> "$HOME/.bashrc"
    fi
    mkdir -p "$POPPY_ROOT"

    # Symlink Poppy Python packages to allow more easily to users to view and modify the code
    for repo in pypot $creature ; do
        # Replace - to _ (I don't like regex)
	module=$(python -c "str = '$repo'; print(str.replace('-','_'))")
	module_path=$(python -c "import $module, os; print(os.path.dirname($module.__file__))")
        ln -s "$module_path" "$POPPY_ROOT"
    done
}

populate_notebooks()
{
    if [ -z "${JUPTER_NOTEBOOK_FOLDER+x}" ]; then
        JUPTER_NOTEBOOK_FOLDER="$HOME/notebooks"
    fi
    mkdir -p "$JUPTER_NOTEBOOK_FOLDER"

    pushd "$JUPTER_NOTEBOOK_FOLDER"

        if [ "$creature" == "poppy-humanoid" ]; then
            repo=https://raw.githubusercontent.com/poppy-project/$creature/$branch
            curl -o Demo_interface.ipynb $repo/software/samples/notebooks/Demo%20Interface.ipynb
        elif [ "$creature" == "poppy-torso" ]; then
            repo=https://raw.githubusercontent.com/poppy-project/$creature/$branch/software/samples/notebooks
            curl -o "Discover your Poppy Torso.ipynb" $repo/Discover%20your%20Poppy%20Torso.ipynb
            curl -o "Record, save and play moves on Poppy Torso.ipynb" $repo/Record%2C%20Save%20and%20Play%20Moves%20on%20Poppy%20Torso.ipynb
            mkdir -p images
            pushd images
              wget $repo/images/poppy_torso.jpg -O poppy_torso.jpg
              wget $repo/images/poppy_torso_motors.png -O poppy_torso_motors.png
            popd
        elif [ "$creature" == "poppy-ergo-jr" ]; then
            repo=https://raw.githubusercontent.com/poppy-project/$creature/$branch/software/samples/notebooks
            curl -o "Discover your Poppy Ergo Jr.ipynb" $repo/Discover%20your%20Poppy%20Ergo%20Jr.ipynb
            curl -o "Record, save and play moves on Poppy Ergo Jr.ipynb" $repo/Record%2C%20Save%20and%20Play%20Moves%20on%20Poppy%20Ergo%20Jr.ipynb
        fi
        repo=https://raw.githubusercontent.com/poppy-project/pypot/$branch/samples/notebooks
        curl -o "Benchmark your Poppy robot.ipynb" $repo/Benchmark%20your%20Poppy%20robot.ipynb

        # Download community notebooks
        wget https://github.com/poppy-project/community-notebooks/archive/master.zip -O master.zip
        unzip master.zip
        mv community-notebooks-master community-notebooks
        rm -f master.zip

        # Copy the documentation pdf
        wget https://www.gitbook.com/download/pdf/book/poppy-project/poppy-docs?lang=en -O documentation.pdf

        ln -s "$POPPY_ROOT" poppy_src
    popd
}

setup_puppet_master()
{
    if [ -z "${POPPY_ROOT+x}" ]; then
        export POPPY_ROOT="$HOME/dev"
        mkdir -p "$POPPY_ROOT"
    fi

    pushd "$POPPY_ROOT"
        wget -O puppet-master.zip "https://github.com/poppy-project/puppet-master/archive/${puppet_master_branch}.zip"
        unzip puppet-master.zip
        rm -f puppet-master.zip
        mv "puppet-master-${puppet_master_branch}" puppet-master

        pushd puppet-master
            pip install flask pyyaml requests
            python bootstrap.py "$hostname" "$creature"
            install_snap "$(pwd)"
        popd
    popd
}

# Called from setup_puppet_master()
install_snap()
{
    pushd "$1"
        wget "https://github.com/jmoenig/Snap--Build-Your-Own-Blocks/archive/${snap_version}.zip" -O "${snap_version}.zip"
        unzip "${snap_version}.zip"
        rm -f "${snap_version}.zip"
        mv "Snap-$snap_version" snap

        pypot_root=$(python -c "import pypot, os; print(os.path.dirname(pypot.__file__))")

        # Delete snap default examples
        rm -rf snap/Examples/EXAMPLES 

        # Snap projects are dynamicaly modified and copied on a local folder for acces rights issues
        # This snap_local_folder is defined depending the OS in pypot.server.snap.get_snap_user_projects_directory()
        snap_local_folder="$HOME/.local/share/pypot"
        mkdir -p "$snap_local_folder"

        # Link pypot Snap projets to Snap! Examples folder
        for project in $pypot_root/server/snap_projects/*.xml; do
            # Local file doesn"t exist yet if SnapRobotServer has not been started
            filename=$(basename "$project")
            cp "$project" "$snap_local_folder/"
            ln -s "$snap_local_folder/$filename" snap/Examples/
            echo -e "$filename\t$filename" >> snap/Examples/EXAMPLES
        done

        ln -s "$snap_local_folder/pypot-snap-blocks.xml" snap/libraries/poppy.xml
        echo -e "poppy.xml\tPoppy robots" >> snap/libraries/LIBRARIES

        wget https://github.com/poppy-project/poppy-monitor/archive/master.zip -O master.zip
        unzip master.zip
        rm -f master.zip
        mv poppy-monitor-master monitor
    popd
}

autostartup_webinterface()
{
    cd || exit

    if [ -z "${POPPY_ROOT+x}" ]; then
        export POPPY_ROOT="$HOME/dev"
        mkdir -p "$POPPY_ROOT"
    fi

    sudo tee /etc/systemd/system/puppet-master.service > /dev/null <<EOF
[Unit]
Description=Puppet Master service
Wants=network-online.target
After=network.target network-online.target
[Service]
PIDFile=/run/puppet-master.pid
Environment="PATH=$PATH"
ExecStart=source $HOME/pyenv/bin/activate && python bouteillederouge.py
User=poppy
Group=poppy
WorkingDirectory=$POPPY_ROOT/puppet-master
Type=simple
[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable puppet-master.service
}

redirect_port80_webinterface()
{
    sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to 2280
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
    sudo apt-get install -y iptables-persistent
}

setup_update()
{
    cd || exit
    wget https://raw.githubusercontent.com/poppy-project/raspoppy/$branch/poppy-update.sh -O "$HOME/.poppy-update.sh"

    cat > poppy-update << EOF
#$HOME/pyenv/bin/python
import os
import yaml
from subprocess import call
with open(os.path.expanduser('~/.poppy_config.yaml')) as f:
    config = yaml.load(f)
with open(config['update']['logfile'], 'w') as f:
    call(['bash', os.path.expanduser('~/.poppy-update.sh'),
          config['update']['url'],
          config['update']['logfile'],
          config['update']['lockfile']], stdout=f, stderr=f)
EOF
    chmod +x poppy-update
    mv poppy-update "$HOME/pyenv/bin/"
}


set_logo()
{
    wget https://raw.githubusercontent.com/poppy-project/raspoppy/master/poppy_logo -O "$HOME/.poppy_logo"
    # Remove old occurences of poppy_logo in .bashrc
    sed -i /poppy_logo/d "$HOME/.bashrc"
    echo cat "$HOME/.poppy_logo" >> "$HOME/.bashrc"
}

install_poppy_libraries
populate_notebooks
setup_puppet_master
autostartup_webinterface
redirect_port80_webinterface
setup_update
set_logo
