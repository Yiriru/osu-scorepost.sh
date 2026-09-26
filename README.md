# osu-scorepost.sh
me trying to automate osu scoreposting uploads
(using it might break your pc cuz my code is worse than chatgpt)

```
Usage: ./osu-scorepost.sh mode arguments [OPTIONS]

Modes available:
  score recent top replay clear

Score mode arguments:
  scoreid

Recent mode arguments:
  (Optional) userid

Top mode arguments:
  (Optional) userid

Replay mode arguments:
  path/to/replay.osr

Options
-h   --help                   Print this and exit.
     --setting name           Use different danser setting.
     --skin    name           Use different skin.
```

config is at the top of the script
```
# Config
clientID=""
clientSecret=""
userid=""
dansercli="$HOME/danser-go/danser-go"
replaydir="$HOME/danser-go/replays"
beatmapdir="$HOME/danser-go/songs"
videodir="$HOME/danser-go/videos"
```

put some efforts into making this so i wanted to share
but still, dont use it
