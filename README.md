# MatrixFS

A small FUSE filesystem that stores data as Matrix state objects, giving you a relatively low-cost distributed filesystem - albeit much slower than any proper filesystem.

## Usage

```
$ bin/mount.matrixfs -h
Usage:
     mount.matrixfs !roomid:example.com mountpoint [-h] [-d] [-o [opt,optkey=value,...]]
Fuse options: (2.9)
    -h                     help - print this help output
    -d |-o debug           enable internal FUSE debug output

fuse: failed to access mountpoint -h: No such file or directory
Filesystem options:
    -o v                             Enables logging of MatrixFS actions
    -o vv                            Enables verbose logging of MatrixFS actions
    -o debug                         Enables logging of MatrixSDK communication
    -o no_listen                     Don't listen to changes
    -o hs=https://matrix.example.com The homeserver URL to communicate with
    -o hs_domain=example.com         The homeserver domain to communicate with
    -o access_token=TOKEN            An access token to use, to skip needing to log in
    -o tokenfile=/PATH/TO/TOKEN      An access token to use, to skip needing to log in
    -o user=USERNAME                 The username to log in with
    -o pass=PASSWORD                 The password to log in with
    -o passfile=/PATH/TO/PASS        The file to read the password from
    -o gc=SECONDS                    Duration to keep file data in memory since last access (default 3600 / 1 hour, use -1 to disable)
```

### Limitations

Due to how Matrix stores state (in 64kB JSON objects) larger files and data that can't be UTF-8 encoded will be fragmented and stored as base64 strings, which will cause a larger memory footprint when accessing them.

There's only limited handling of umasks; the three octets will always be identical, read will always be set, write will be set depending on the power levels of the mounting user, execute can only be set through a separate Matrix client.

## TODO?

- Sync existence and content separately?
- Handle multiple rooms
- Access arbitrary state?
- Support chmod for setting execute bit

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ananace/ruby-matrix-fs

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
