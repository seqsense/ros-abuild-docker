# ros-abuild-docker

Alpine Linux package builder for ROS (Robot Operating System)

## Build builder container

```shell
docker build -t alpineros/ros-abuild:3.11-noetic .
```

or pull from GitHub Container Registry

```shell
docker pull ghcr.io/alpine-ros/ros-abuild:3.11-noetic
docker tag ghcr.io/alpine-ros/ros-abuild:3.11-noetic alpineros/ros-abuild:3.11-noetic
```

## Build ROS package(s)

In ROS package directory:
```shell
docker run -it --rm \
  -v $(pwd):/src/$(basename $(pwd)):ro \
  alpineros/ros-abuild:3.11-noetic
```

In ROS meta-package root directory:
```shell
docker run -it --rm \
  -v $(pwd):/src:ro \
  alpineros/ros-abuild:3.11-noetic
```

To get generated apk package,
1. Create a directory to store packages.
    ```shell
    mkdir -p /path/to/your/packages
    ```
2. Build with following arguments:
    ```
    -v /path/to/your/packages:/packages
    ```

If `*.rosinstall` file is present, packages specified in the file will be automatically cloned and built.
