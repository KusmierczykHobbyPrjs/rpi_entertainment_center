# Yle Areena (Finnish public broadcaster)

Install `plugin.video.yleareena.jade.zip` from inside Kodi:

    Settings > Add-ons > Install from zip file

Most Yle content is geo-restricted to Finland, so connect the VPN first:

    bash bin/nordvpn_connect.sh fi

## How the zip was built

Only the packaged zip is kept in this repository. To rebuild it from a newer
upstream release:

    git clone https://github.com/aajanki/plugin.video.yleareena.jade.git
    cd plugin.video.yleareena.jade
    bash package.sh

Do not commit the unpacked clone — it carries its own `.git` directory, which
git records as a broken submodule reference.

## References

 - Repository:   https://github.com/aajanki/plugin.video.yleareena.jade
 - Instructions: https://www.huoltovalikko.com/threads/kodi-yle-areena-2022.15190/


# Instructions: https://www.huoltovalikko.com/threads/kodi-yle-areena-2022.15190/
# Repo: https://github.com/aajanki/plugin.video.yleareena.jade
