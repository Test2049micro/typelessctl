tell application "System Events"
	if not (exists process "Typeless") then return ""
	tell process "Typeless"
		set closed to {}
		repeat with w in windows
			try
				set n to name of w
				if (n is "Typeless") or (n starts with "Onboarding") then
					click button 1 of w
					set end of closed to n
				end if
			end try
		end repeat
		if closed is {} then return ""
		set AppleScript's text item delimiters to ","
		return closed as string
	end tell
end tell
