-- Alfred → Alacritty + tmux integration
-- Type '>' in Alfred to run commands in a dedicated "alfred" tmux session.

on alfred_script(q)
	set tmux to "/opt/homebrew/bin/tmux"

	-- Send command to existing "alfred" tmux session, or create one
	do shell script tmux & " has-session -t alfred 2>/dev/null && " & tmux & " send-keys -t alfred " & quoted form of q & " Enter || " & tmux & " new-session -d -s alfred " & quoted form of q

	-- If an Alacritty window is already attached to the session, raise it
	set _found to false
	if application "Alacritty" is running then
		tell application "System Events"
			tell (first application process whose name is "alacritty")
				repeat with w in windows
					if name of w contains "alfred" then
						perform action "AXRaise" of w
						set _found to true
						exit repeat
					end if
				end repeat
			end tell
		end tell
	end if

	if not _found then
		-- Launch Alacritty with a shell that attaches to the tmux session
		do shell script "open -na Alacritty --args -e " & tmux & " attach-session -t alfred"
		-- Wait for window
		tell application "System Events"
			repeat 100 times
				delay 0.05
				if application "Alacritty" is running then
					try
						if (count windows of (first application process whose name is "alacritty")) > 0 then exit repeat
					end try
				end if
			end repeat
		end tell
	end if

	tell application "Alacritty" to activate
end alfred_script
