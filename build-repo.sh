#!/bin/sh

set -e

repo=${ROS_DISTRO}

if [ ! -f ${PACKAGER_PRIVKEY} ]; then
  abuild-keygen -a -i -n

  # Re-sign packages if private key is updated
  index=$(find ${REPODIR} -name APKINDEX.tar.gz || true)
  if [ -f "${index}" ]; then
    rm -f ${index}
    apk index -o ${index} `find $(dirname ${index}) -name '*.apk'`
    abuild-sign -k /home/builder/.abuild/*.rsa ${index}
  fi
fi

mkdir -p ${APORTSDIR}/${repo}
mkdir -p ${REPODIR}
mkdir -p ${LOGDIR}

extsrc=${HOME}/extsrc
mkdir -p ${extsrc}

summary_file=${LOGDIR}/summary.log
full_log_file=${LOGDIR}/full.log


# Update repositories

if [ ! -z ${CUSTOM_APK_REPOS} ]; then
  for r in ${CUSTOM_APK_REPOS}; do
    echo $r | sudo tee -a /etc/apk/repositories
  done
fi
echo "${REPODIR}/${repo}" | sudo tee -a /etc/apk/repositories
sudo apk update
rosdep update


# Clone packages if .rosinstall is provided

ext_deps=$(find ${SRCDIR} -name "*.rosinstall" || true)
tmp_ws=$(mktemp -d)
touch ${tmp_ws}/.rosinstall
for dep in ${ext_deps}; do
  wstool merge -y -t ${tmp_ws} $dep
done
if [ -s ${tmp_ws}/.rosinstall ]; then
  wstool init ${extsrc} ${tmp_ws}/.rosinstall --shallow -j4
fi


# Generate APKBUILDs

manifests="`find ${SRCDIR} -name "package.xml"` `find ${extsrc} -name "package.xml"`"
for manifest in ${manifests}; do
  echo +++++++++++++++++++++++++
  echo ${manifest}
  pkgpath=$(dirname ${manifest})
  pkgname=$(basename ${pkgpath})

  commit_date=$(git -C ${pkgpath} show \
                -s --format=%ad --date=format:'%Y%m%d%H%M%S' HEAD)

  # Copy files with filter
  mkdir -p ${APORTSDIR}/${repo}/${pkgname}
  files=$(ls -1A ${pkgpath})
  for file in ${files}; do
    if [ $file == ".git" ]; then continue; fi

    cp -r ${pkgpath}/${file} ${APORTSDIR}/${repo}/${pkgname}/${file}
  done

  (set -o pipefail && /usr/bin/env python3 /scripts/genapkbuild.py \
    ${repo} ${APORTSDIR}/${repo}/${pkgname}/package.xml --src \
      --ver-suffix=_git${commit_date} \
      | tee ${APORTSDIR}/${repo}/${pkgname}/APKBUILD) \
    || (echo "## Package dependency failure" >> ${summary_file} && false)
done

rm -f $(find ${APORTSDIR} -name "ros-abuild-build.log")
rm -f $(find ${APORTSDIR} -name "ros-abuild-check.log")
rm -f $(find ${APORTSDIR} -name "ros-abuild-status.log")


# Build everything

GENERATE_BUILD_LOGS=yes buildrepo -k -d ${REPODIR} -a ${APORTSDIR} ${repo} | tee ${full_log_file}


# Summarize build result

function summarize_error() {
  error_text=$(grep -A5 -i -E "$2" $1 || true)
  lines=$(echo -n "${error_text}" | wc -l)

  # print summary
  if [ ${lines} -lt 1 ]; then
    echo 'no build error detected'
  else
    echo "${error_text}" | head -n30
    if [ ${lines} -gt 30 ]; then
      echo "error log exceeded 30 lines (total ${lines} lines)"
    fi
  fi
}

rm -f ${summary_file}

echo "## Summary" >> ${summary_file}
echo '```' >> ${summary_file}
tail -n6 ${full_log_file} >> ${summary_file}
echo '```' >> ${summary_file}

error=false
for manifest in ${manifests}; do
  srcpath=$(dirname ${manifest})
  pkgname=$(basename ${srcpath})
  pkgpath=${APORTSDIR}/${repo}/${pkgname}

  apk_filename=$(. ${pkgpath}/APKBUILD; echo "${pkgname}-${pkgver}-r${pkgrel}.apk")

  echo >> ${summary_file}
  echo "## $pkgname" >> ${summary_file}
  echo "**${apk_filename}**" >> ${summary_file}

  if [ ! -f ${pkgpath}/apk-build-temporary/ros-abuild-status.log ]; then
    if [ -f ${REPODIR}/${repo}/*/${apk_filename} ]; then
      echo "Already been built." >> ${summary_file}
    else
      echo "Failed to start build. The package might have unsatisfied dependencies." >> ${summary_file}
      error=True
    fi
    continue
  fi
  if grep "finished" ${pkgpath}/apk-build-temporary/ros-abuild-status.log > /dev/null; then
    echo "Build succeeded." >> ${summary_file}
    if grep "Check skipped" ${pkgpath}/apk-build-temporary/ros-abuild-check.log > /dev/null; then
      echo "(NOCHECK)" >> ${summary_file}
    fi
    if [ ! -f ${REPODIR}/${repo}/*/${apk_filename} ]; then
      echo "Failed to generate package." >> ${summary_file}
      error=True
    fi
    continue
  fi

  error=true

  echo "### Build log" >> ${summary_file}
  if [ ! -f ${pkgpath}/apk-build-temporary/ros-abuild-build.log ]; then
    echo "Build log not found" >> ${summary_file}
    continue
  fi
  echo "\`\`\`" >> ${summary_file}
  summarize_error ${pkgpath}/apk-build-temporary/ros-abuild-build.log "error" >> ${summary_file}
  echo "\`\`\`" >> ${summary_file}

  if [ -f ${pkgpath}/apk-build-temporary/ros-abuild-check.log ]; then
    echo "### Check log" >> ${summary_file}
    echo '```' >> ${summary_file}
    summarize_error ${pkgpath}/apk-build-temporary/ros-abuild-check.log "(error|failure)" >> ${summary_file}
    echo '```' >> ${summary_file}
    continue
  fi
done

echo
echo "---"
cat ${summary_file}

if [ $error == "true" ]; then
  exit 1
fi

exit 0
