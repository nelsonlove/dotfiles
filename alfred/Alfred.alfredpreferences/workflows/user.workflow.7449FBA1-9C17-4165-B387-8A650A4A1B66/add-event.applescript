to convertDate(textDate) -- adapted from https://gist.github.com/RichardHyde/3386ac57b55455b71140
	set resultDate to the current date
	set the month of resultDate to (1 as integer)
	set the day of resultDate to (1 as integer)
	set the year of resultDate to (text 1 thru 4 of textDate)
	set the month of resultDate to (text 6 thru 7 of textDate)
	set the day of resultDate to (text 9 thru 10 of textDate)
	set the hours of resultDate to (text 12 thru 13 of textDate)
	set the minutes of resultDate to (text 15 thru 16 of textDate)
		set the seconds of resultDate to (text 18 thru 19 of textDate)
	return resultDate
end convertDate

set envStartDate to system attribute "start_date"
set theStartDate to convertDate(envStartDate)

set envEndDate to system attribute "end_date"
set theEndDate to convertDate(envEndDate)

set theSummary to system attribute "summary"
set theCalendar to system attribute "calendar"

tell application "Calendar"
	tell calendar theCalendar
		make new event with properties {summary:theSummary, start date:theStartDate, end date:theEndDate}
	end tell
end tell
