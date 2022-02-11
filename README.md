# sys_appearance
##### get real time notifications of mac OS system appearance changes through a TCP socket

`sys_appearance` is a small mac OS utility that makes it easy for third party applications to get real time notifications of mac OS system appearance, as well as the current appearance.

This tool is meant to replace the rust implementation in [dark-notify](https://github.com/cormacrelf/dark-notify), because it uses nightly APIs which were unstable and no longer exist in recent versions of rust.

## Installation

```sh
make
```

## License

BSD 2-Clause License
