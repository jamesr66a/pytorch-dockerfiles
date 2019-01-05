#!/bin/bash

set -ex

# Optionally install conda
if [ -n "$ANACONDA_PYTHON_VERSION" ]; then
  BASE_URL="https://repo.continuum.io/miniconda"

  MAJOR_PYTHON_VERSION=$(echo "$ANACONDA_PYTHON_VERSION" | cut -d . -f 1)

  case "$MAJOR_PYTHON_VERSION" in
    2)
      CONDA_FILE="Miniconda2-latest-Linux-x86_64.sh"
    ;;
    3)
      CONDA_FILE="Miniconda3-latest-Linux-x86_64.sh"
    ;;
    *)
      echo "Unsupported ANACONDA_PYTHON_VERSION: $ANACONDA_PYTHON_VERSION"
      exit 1
      ;;
  esac

  mkdir /opt/conda
  chown jenkins:jenkins /opt/conda

  as_jenkins() {
    # NB: unsetting the environment variables works around a conda bug
    # https://github.com/conda/conda/issues/6576
    # NB: Pass on PATH and LD_LIBRARY_PATH to sudo invocation
    sudo -H -u jenkins env -u SUDO_UID -u SUDO_GID -u SUDO_COMMAND -u SUDO_USER env "PATH=$PATH" "LD_LIBRARY_PATH=$LD_LIBRARY_PATH" $*
  }

  pushd /tmp
  wget -q "${BASE_URL}/${CONDA_FILE}"
  chmod +x "${CONDA_FILE}"
  as_jenkins ./"${CONDA_FILE}" -b -f -p "/opt/conda"
  popd

  # NB: Don't do this, rely on the rpath to get it right
  #echo "/opt/conda/lib" > /etc/ld.so.conf.d/conda-python.conf
  #ldconfig
  sed -e 's|PATH="\(.*\)"|PATH="/opt/conda/bin:\1"|g' -i /etc/environment
  export PATH="/opt/conda/bin:$PATH"

  # Track latest conda update
  as_jenkins conda update -n base conda

  # Install correct Python version
  as_jenkins conda install python="$ANACONDA_PYTHON_VERSION"

  conda_install() {
    # Ensure that the install command don't upgrade/downgrade Python
    # This should be called as
    #   conda_install pkg1 pkg2 ... [-c channel]
    as_jenkins conda install -q -y python="$ANACONDA_PYTHON_VERSION" $*
  }

  # Install PyTorch conda deps, as per https://github.com/pytorch/pytorch README
  # DO NOT install cmake here as it would install a version newer than 3.5, but
  # we want to pin to version 3.5.
  conda_install numpy pyyaml mkl mkl-include setuptools cffi typing future six
  if [[ "$CUDA_VERSION" == 8.0* ]]; then
    conda_install magma-cuda80 -c soumith
  elif [[ "$CUDA_VERSION" == 9.0* ]]; then
    conda_install magma-cuda90 -c soumith
  elif [[ "$CUDA_VERSION" == 9.1* ]]; then
    conda_install magma-cuda91 -c soumith
  elif [[ "$CUDA_VERSION" == 9.2* ]]; then
    conda_install magma-cuda92 -c soumith
  fi

  # TODO: This isn't working atm
  conda_install nnpack -c killeent

  # Install some other packages
  # TODO: Why is scipy pinned
  as_jenkins pip install -q pytest scipy==1.1.0 scikit-image librosa>=0.6.2 psutil
fi
