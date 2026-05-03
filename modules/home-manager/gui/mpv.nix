{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.gui.mpv;
in
{
  options.user.gui.mpv = {
    enable = lib.mkEnableOption "mpv";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.nodejs
    ];

    programs.mpv = {
      enable = true;
      config = {
        profile = "gpu-hq";
        scale = "ewa_lanczossharp";
        cscale = "ewa_lanczossharp";
        "video-sync" = "display-resample";
        interpolation = true;
        tscale = "oversample";
        hwdec = "method";
        "hwdec-codecs" = "all";
        osc = "no";
        loop = true;
        "force-seekable" = true;
        "screenshot-template" = "%x/Screenshot-%F-T%wH.%wM.%wS.%wT-F%{estimated-frame-number}";
      };
      bindings = {
        "Alt+Enter" = "cycle fullscreen";
        "Esc" = "quit";
        "WHEEL_UP" = "seek 10";
        "WHEEL_DOWN" = "seek -10";
        "Ctrl+WHEEL_UP" = "seek 1";
        "Ctrl+WHEEL_DOWN" = "seek -1";
        "Shift+WHEEL_UP" = "seek 100";
        "Shift+WHEEL_DOWN" = "seek -100";
        "Alt+RIGHT" = "add chapter 1";
        "Alt+LEFT" = "add chapter -1";
        "UP" = "add volume +5";
        "DOWN" = "add volume -5";
        "RIGHT" = "seek 0.01 keyframes";
        "LEFT" = "seek -0.01 keyframes";
        a = "cycle audio";
        s = "cycle sub";
        "shift+s" = "screenshot";
      };
      scriptOpts = {
        osc = {
          visibility = "never";
        };
      };
    };

    home.file = {
      ".config/mpv/scripts/mpv-cut/main.lua".text = ''
        utils = require "mp.utils"

        mp.msg.info("MPV-CUT LOADED.")

        --- settings
        KEY_CUT = "c"
        KEY_CYCLE_ACTION = "g"

        --- defaults
        ACTIONS = { "COPY", "GIF" }
        ACTION = ACTIONS[1]
        MAKE_CUTS_SCRIPT_PATH = utils.join_path(mp.get_script_directory(), "make_cuts")
        START_TIME = nil

        local function print(s)
        	mp.msg.info(s)
        	mp.osd_message(s)
        end

        text_overlay = mp.create_osd_overlay("ass-events")
        text_overlay.hidden = true
        text_overlay:update()

        local function text_overlay_off()
        	text_overlay:update()
        	text_overlay.hidden = true
        	text_overlay:update()
        end


        local function text_overlay_on()
        	text_overlay.data = string.format("%s from %s", ACTION, START_TIME)
        	text_overlay.hidden = false
        	text_overlay:update()
        end

        local function print_or_update_text_overlay(content)
        	if START_TIME then text_overlay_on() else print(content) end
        end

        local function index_of(list, string)
        	local index = 1
        	while index < #list do
        		if list[index] == string then return index end
        		index = index + 1
        	end
        	return 0
        end

        local function cycle_action()
        	ACTION = ACTIONS[index_of(ACTIONS, ACTION) + 1]
        	print_or_update_text_overlay("ACTION: " .. ACTION)
        end

        local function get_file_info()
        	local inpath = mp.get_property("path")
        	local filename = mp.get_property("filename")
        	return inpath, filename
        end

        local function print_async_result(success, result, error)
        	print("Done")
        end

        local function make_cut(json_string)
        	local inpath, filename = get_file_info()
        	local indir = utils.split_path(inpath)
        	local args = { "node", MAKE_CUTS_SCRIPT_PATH, indir }
        	table.insert(args, json_string)
        	print("Making cut")
        	mp.command_native_async({
        			name = "subprocess",
        			playback_only = false,
        			args = args,
        		}, print_async_result)
        end

        local function cut(start_time, end_time)
        	local inpath, filename = get_file_info()
        	local json_string = "{ "
        		.. string.format("%q: %q", "filename", filename)
        		.. string.format(", %q: %q", "action", ACTION)
        		.. string.format(", %q: %q", "start_time", start_time)
        		.. string.format(", %q: %q", "end_time", end_time)
        		.. " }\n"
            make_cut(json_string)
        end

        local function put_time()
        	local time = mp.get_property_number("time-pos")
        	if not START_TIME then
        		START_TIME = time
        		text_overlay_on()
        		return
        	end
        	text_overlay_off()
        	if time > START_TIME then
        		cut(START_TIME, time)
        		START_TIME = nil
        	else
        		print("INVALID")
        		START_TIME = nil
        	end
        end

        mp.add_key_binding(KEY_CUT, "cut", put_time)
        mp.add_key_binding(KEY_CYCLE_ACTION, "cycle_action", cycle_action)
      '';
      ".config/mpv/scripts/mpv-cut/make_cuts".text = ''
        #! /usr/bin/env node

        function iter$__(a){ let v; return a ? ((v=a.toIterable) ? v.call(a) : a) : a; };

        /*body*/
        let {readFileSync: readFileSync,statSync: statSync} = require('fs');
        let {spawnSync: spawnSync} = require('child_process');
        let path = require("path");

        let p = console.log;
        let red = "\x1b[31m";
        let plain = "\x1b[0m";
        let green = "\x1b[32m";
        let purple = "\x1b[34m";

        p("IN MAKE_CUTS");

        function quit(s){
        	p((("" + red + s + ", quitting." + plain + "\n"));
        	return process.exit();
        };

        function is_dir(s){
        	try {
        		if (statSync(s).isDirectory()) { return true };
        	} catch ($1) {
        		return false;
        	};
        };

        function parse_json(data){
        	let failed = new Set();
        	let succeeded = new Set();

        	for (let $2 = 0, $3 = iter$__(data.split('\n')), $5 = $3.length; $2 < $5; $2++) {
        		let line = $3[$2];
        		line = line.trim();
        		if (line.length < 1) { continue; };
        		try {
        			JSON.parse(line);
        			succeeded.add(line);
        		} catch ($4) {
        			failed.add(line);
        		};
        	};

        	failed = [...failed];
        	succeeded = [...succeeded];

        	failed.length > 0 && p(("\n" + red + "Failed to load JSON for lines:" + plain + " " + failed));
        	succeeded.length > 0 && p(("\n" + green + "Cut list:" + plain + " " + succeeded + "\n"));

        	return succeeded.map(function(x) { return JSON.parse(x); });
        };

        function to_hms(secs){
        	return [
        		Math.floor(secs / 3600),
        		Math.floor((secs % 3600) / 60),
        		Math.floor(Math.round((secs % 3600 % 60) * 1000) / 1000)
        	].join("-");
        };

        function main(){
        	let argv = process.argv.slice(2);
        	p("ARGS:");
        	p(argv);
        	let json = argv.pop();
        	let indir;
        	let outdir;
        	switch (argv.length) {
        		case 0: {
        			indir = outdir = ".";
        			break;
        		}
        		case 1: {
        			indir = outdir = argv.pop();
        			break;
        		}
        		case 2: {
        			[indir,outdir] = argv;
        			break;
        		}
        		default:
        			quit(("Invalid args: " + (process.argv)));

        	};

        	let cut_list = parse_json(json);
        	if (cut_list.length < 1) { quit("No valid cuts") };

        	if (!(is_dir(indir))) { quit("Input directory is invalid") };
        	if (!(is_dir(outdir))) { quit("Output directory is invalid") };

        	for (let index = 0, $6 = iter$__(cut_list), $7 = $6.length; index < $7; index++) {
        		let cut = $6[index];
        		let {filename: filename,action: action,start_time: start_time,end_time: end_time} = cut;
        		let {name: filename_noext,ext: ext} = path.parse(filename);
        		let duration = parseFloat(end_time) - parseFloat(start_time);

                let my_ext;
                if (action == "GIF") {
                    my_ext = ".gif";
                } else {
                    my_ext = ext;
                }

        		cut_name = (filename_noext + "_FROM_" + to_hms(start_time) + "_TO_" + to_hms(end_time) + my_ext);

        		let inpath = path.join(indir,filename);
        		let outpath = path.join(outdir,cut_name);

        		let cmd = "ffmpeg";
        		let args = [
        			"-nostdin","-y",
        			"-loglevel","error",
        			"-ss",start_time,
        			"-t",duration,
        			"-i",inpath,
        		];

        		if (action == "GIF") {
        			args.push(
                        "-vf", "fps=12,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse",
                        "-loop", "0"
        			);
        		} else {
        			args.push(
        				"-c","copy",
        				"-avoid_negative_ts","make_zero"
        			);
        		};

        		args.push(outpath);

        		let progress = ("(" + (index + 1) + "/" + (cut_list.length) + ")");
        		let cmd_str = (("" + cmd + " " + args.join(" ")));

        		p((("" + green + progress + plain + " " + inpath + " " + green + "->" + plain)));
        		p((("" + outpath + "\n")));
        		p((("" + purple + cmd_str + plain + "\n")));

        		spawnSync(cmd,args,{stdio: 'inherit'});
        	};

        	return p("Done.\n");
        };

        main();
      '';
    };
  };
}
