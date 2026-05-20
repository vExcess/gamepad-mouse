# gamepad-mouse
Use your controller as a mouse.

Demo: [https://www.youtube.com/watch?v=T4tdVj46XFc](https://www.youtube.com/watch?v=T4tdVj46XFc)

## Bindings
Left Joystick -> mouse movement  
Right Joystick -> mouse scrolling  
East Button (B on xbox) -> right click  
South Button (A on xbox) -> left click  
West Button (X on xbox) -> left click  
North Button (Y on xbox) -> middle click  

## Controllers With Verified Support
- 8Bitdo Ultimate 2C

## Controllers With Planned Support
- Steam Controller 2 (when I can buy one)

## Planned Features
- Add an on-screen keyboard feature
- Support displays faster than 60 FPS
- Support user-modifiable config file
- Support Wayland
- Gracefully handle controller disconnects

## Build & Install
gamepad-mouse uses jvbuild ([https://github.com/vExcess/jvbuild](https://github.com/vExcess/jvbuild)) as its build system.

gamepad-mouse is written in Zig 0.15.2 ([https://ziglang.org/download/](https://ziglang.org/download/))

```sh
# get source
git clone https://github.com/vExcess/gamepad-mouse.git
cd gamepad-mouse

# install dependencies
jvbuild install

# compile the project
jvbuild build -O=Fast

# package the project
jvbuild package

# install gamepad-mouse
sudo apt install ./jvbuild-out/gamepad-mouse_1.0.0_amd64.deb

# run it (it likely won't work without sudo)
sudo gamepad-mouse
```

## Helpful Resources
- [https://ruby0x1.github.io/machinery_blog_archive/post/gamepad-implementation-on-linux/index.html](https://ruby0x1.github.io/machinery_blog_archive/post/gamepad-implementation-on-linux/index.html)
- [https://tronche.com/gui/x/xlib/window-information/XQueryPointer.html](https://tronche.com/gui/x/xlib/window-information/XQueryPointer.html)
- [https://linux.die.net/man/3/xtestfakebuttonevent](https://linux.die.net/man/3/xtestfakebuttonevent)
- [https://github.com/jordansissel/xdotool](https://github.com/jordansissel/xdotool)

## Troubleshooting
If bluetooth controller not detecting as HID device, run the following to reset the controller:
```
bluetoothctl
select E4:17:D8:4A:DF:E0 # replace with your bluetooth address
disconnect
remove E4:17:D8:4A:DF:E0
scan on
pair E4:17:D8:4A:DF:E0
trust E4:17:D8:4A:DF:E0
connect E4:17:D8:4A:DF:E0
```