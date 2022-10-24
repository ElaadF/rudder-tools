############################################
# Add rudder repository to package manager #
############################################
add_repo() {
  # if the version is a file or a URL stop here
  if [ -f "${RUDDER_VERSION}" ] || echo "${RUDDER_VERSION}" | grep "^http" > /dev/null
  then
    return
  fi

  # Make Repository URL
  [ "${PM}" = "apt" ] && REPO_TYPE="apt"
  [ "${PM}" = "yum" ] && REPO_TYPE="rpm"
  [ "${PM}" = "zypper" ] && REPO_TYPE="rpm"
  [ "${PM}" = "rpm" ] && REPO_TYPE="rpm"
  [ "${PM}" = "pkg" ] && REPO_TYPE="misc/solaris"
  if [ "${USE_HTTPS}" != "false" ]; then
    S="s"
    [ "${PM}" = "apt" ] && ${PM_INSTALL} apt-transport-https
  else
    S=""
  fi


  # On sles we need to urlencode the password or if it contains special chars it won't be able to
  # add the repo

  if [ "${DOWNLOAD_USER}" = "" ]; then
    USER=""
  elif [ "${PM}" = "zypper" ]; then
    URLENCODED_PASSWORD=$(echo "${DOWNLOAD_PASSWORD}" | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
    USER="${DOWNLOAD_USER}:${URLENCODED_PASSWORD}@"
  elif [ "${OS_COMPATIBLE}" = "UBUNTU" -o "${OS_COMPATIBLE}" = "DEBIAN" ]; then
    USER=""
  else
    USER="${DOWNLOAD_USER}:${DOWNLOAD_PASSWORD}@"
  fi

  if [ "${USE_CI}" = "yes" ]
  then
    HOST="publisher.normation.com"
  else
    if [ "${DOWNLOAD_USER}" = "" ]; then
      HOST="repository.rudder.io"
    else
      HOST="${USER}download.rudder.io"
    fi
  fi
  URL_BASE="http${S}://${HOST}/${REPO_PREFIX}${REPO_TYPE}/${RUDDER_VERSION}"

  if [ "${PM}" = "yum" ] || [ "${PM}" = "rpm" ] || [ "${PM}" = "zypper" ]
  then
    URL_BASE="${URL_BASE}/${OS_COMPATIBLE}_${OS_MAJOR_VERSION}"
  elif [ "${PM}" = "pkg" ]
  then
    URL_BASE="${URL_BASE}/$(echo ${OS_COMPATIBLE} | tr '[:upper:]' '[:lower:]')-${OS_COMPATIBLE_VERSION}"
  fi

  # add repository
  if [ "${PM}" = "apt" ]
  then
    if [ "${OS_COMPATIBLE}" = "UBUNTU" -a $(echo ${OS_COMPATIBLE_VERSION}|cut -d. -f1) -le 10 ] ||
       [ "${OS_COMPATIBLE}" = "DEBIAN" -a $(echo ${OS_COMPATIBLE_VERSION}|cut -d. -f1) -le 6 ]
    then
      # old Debian / Ubuntu like
      ${PM_INSTALL} -y --force-yes gnupg
      get - "http${S}://repository.rudder.io/apt/rudder_apt_key.pub" | apt-key add -
    else
      # Debian / Ubuntu like
      get /etc/apt/trusted.gpg.d/rudder_apt_key.gpg "https://repository.rudder.io/apt/rudder_apt_key.gpg"
    fi

    # the source configuration
    cat > /etc/apt/sources.list.d/rudder.list << EOF
deb ${URL_BASE}/ ${OS_CODENAME} main
EOF

    # source password
    if [ "${DOWNLOAD_USER}" != "" ]; then
      if [ "${OS_COMPATIBLE}" = "UBUNTU" -a $(echo ${OS_COMPATIBLE_VERSION}|cut -d. -f1) -lt 20 ] ||
         [ "${OS_COMPATIBLE}" = "DEBIAN" -a $(echo ${OS_COMPATIBLE_VERSION}|cut -d. -f1) -lt 10 ]
      then
        # old distro don't have an apt/auth.conf.d
        AUTH_CONF="/etc/apt/auth.conf"
      else
        AUTH_CONF="/etc/apt/auth.conf.d/rudder.conf"
      fi

      URLENCODED_PASSWORD=$(echo "${DOWNLOAD_PASSWORD}" | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
      echo "machine download.rudder.io login ${DOWNLOAD_USER} password ${URLENCODED_PASSWORD}" >> "${AUTH_CONF}"
      chmod 640 ${AUTH_CONF}
    fi

    ${PM_UPDATE}
    return 0

  elif [ "${PM}" = "yum" ]
  then
    # Add RHEL like rpm repo
    cat > /etc/yum.repos.d/rudder.repo << EOF
[Rudder]
name=Rudder ${RUDDER_VERSION} Repository
baseurl=${URL_BASE}/
gpgcheck=1
gpgkey=http${S}://repository.rudder.io/rpm/rudder_rpm_key.pub
EOF
    # CentOS 5 only supports importing keys from files
    get "/tmp/rudder_rpm_key.pub" "http${S}://repository.rudder.io/rpm/rudder_rpm_key.pub"
    rpm --import "/tmp/rudder_rpm_key.pub"
    rm "/tmp/rudder_rpm_key.pub"
    return 0

  elif [ "${PM}" = "zypper" ]
  then
    cat > /tmp/rudder.repo << EOF
[Rudder]
enable=1
autorefresh=0
baseurl=${URL_BASE}/
type=rpm-md
EOF
    # Add SuSE repo
    # SLES11 only supports importing keys from files
    get "/tmp/rudder_rpm_key.pub" "http${S}://repository.rudder.io/rpm/rudder_rpm_key.pub"
    rpm --import "/tmp/rudder_rpm_key.pub"
    rm "/tmp/rudder_rpm_key.pub"
    zypper removerepo Rudder || true
    zypper --non-interactive addrepo /tmp/rudder.repo || true
    ${PM_UPDATE}
    return 0
  elif [ "${PM}" = "rpm" ]
  then
    # No repo management, install directly
    return 0
  elif [ "${PM}" = "pkg" ]
  then
    pkg set-publisher -g "${URL_BASE}/" normation
  fi

  # TODO pkgng emerge pacman smartos
  echo "Sorry your Package Manager is not *yet* supported !"
  return 1
}

update_repo() {
  # nothing to update
  if [ "${RUDDER_VERSION}" = "" ]
  then
    return
  fi

  # if the version is a file or a URL stop here
  if [ -f "${RUDDER_VERSION}" ] || echo "${RUDDER_VERSION}" | grep "^http" > /dev/null
  then
    return
  fi

  if [ "${PM}" = "apt" ]
  then
    file=/etc/apt/sources.list.d/rudder.list
    REPO_TYPE="apt"
  elif [ "${PM}" = "yum" ]
  then
    file=/etc/yum.repos.d/rudder.repo
    REPO_TYPE="rpm"
  elif [ "${PM}" = "zypper" ]
  then
    file=/etc/zypp/repos.d/Rudder.repo
    REPO_TYPE="rpm"
  elif [ "${PM}" = "pkg" ]
  then
    URL_BASE=$(LANG=C pkg publisher | grep ^normation | awk '{print $5}' | sed "s%misc/solaris/\(latest\|nightly\|[0-9.]\+\(-nightly\|~beta[0-9]\+\|~rc[0-9]\+\)\?\)/%misc/solaris/${RUDDER_VERSION}/%")
    pkg set-publisher -g "${URL_BASE}/" normation
    return
  else
    echo "Sorry your Package Manager is not *yet* supported !"
    return 1
  fi

  # The real edit
  sed -i "s%${REPO_TYPE}/\(latest\|nightly\|[0-9.]\+\(-nightly\|~beta[0-9]\+\|~rc[0-9]\+\)\?\)/%${REPO_TYPE}/${RUDDER_VERSION}/%" "${file}"

  if [ "${PM}" = "apt" ] || [ "${PM}" = "zypper" ]
  then
    ${PM_UPDATE}
  fi
}

remove_repo() {
  # if the version is a file or a URL stop here
  if [ -f "${RUDDER_VERSION}" ] || echo "${RUDDER_VERSION}" | grep "^http" > /dev/null
  then
    return
  fi

  if [ "${PM}" = "apt" ]
  then
    rm -f /etc/apt/sources.list.d/rudder.list
  elif [ "${PM}" = "yum" ]
  then
    rm -f /etc/yum.repos.d/rudder.repo
  elif [ "${PM}" = "zypper" ]
  then
    zypper removerepo Rudder || true
  elif [ "${PM}" = "pkg" ]
  then
    pkg unset-publisher normation
  fi
}

can_remove_repo() {
  if [ "${FORGET_CREDENTIALS}" = "true" ]
  then
    remove_repo
  fi
}
