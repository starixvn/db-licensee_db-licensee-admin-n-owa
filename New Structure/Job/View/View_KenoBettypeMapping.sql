USE [bodb02]
GO

/****** Object:  View [dbo].[View_KenoBettypeMapping]    Script Date: 05/03/2015 16:15:48 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE VIEW [dbo].[View_KenoBettypeMapping]
AS

/*  
	Created: 20150303@Florent
	Task : Keno Winloss report
	DB: DBEXT.bodb02
*/

	  SELECT 1	AS ChoiceId, 'Big'			AS ChoiceName, 1	 AS BettypeID, 'Big/Small'			AS BettypeName
UNION SELECT 2	AS ChoiceId, 'Small' 		AS ChoiceName, 1	 AS BettypeID, 'Big/Small'			AS BettypeName
UNION SELECT 3	AS ChoiceId, 'Odd' 			AS ChoiceName, 2	 AS BettypeID, 'Odd/Even'			AS BettypeName
UNION SELECT 4	AS ChoiceId, 'Even' 		AS ChoiceName, 2	 AS BettypeID, 'Odd/Even'			AS BettypeName
UNION SELECT 5	AS ChoiceId, 'Up' 			AS ChoiceName, 3	 AS BettypeID, 'Up/Down'			AS BettypeName
UNION SELECT 6	AS ChoiceId, 'Tie' 			AS ChoiceName, 3	 AS BettypeID, 'Up/Down'			AS BettypeName
UNION SELECT 7	AS ChoiceId, 'Down' 		AS ChoiceName, 3	 AS BettypeID, 'Up/Down'			AS BettypeName
UNION SELECT 8	AS ChoiceId, 'Odds' 		AS ChoiceName, 4	 AS BettypeID, 'Odds/Evens'			AS BettypeName
UNION SELECT 9	AS ChoiceId, 'Tie' 			AS ChoiceName, 4	 AS BettypeID, 'Odds/Evens'			AS BettypeName
UNION SELECT 10 AS ChoiceId, 'Evens' 		AS ChoiceName, 4	 AS BettypeID, 'Odds/Evens'			AS BettypeName
UNION SELECT 11 AS ChoiceId, 'Big Odd' 		AS ChoiceName, 5	 AS BettypeID, 'Big Small/Odd Even' AS BettypeName
UNION SELECT 12 AS ChoiceId, 'Big Even'		AS ChoiceName, 5	 AS BettypeID, 'Big Small/Odd Even' AS BettypeName
UNION SELECT 13 AS ChoiceId, 'Small Odd'	AS ChoiceName, 5	 AS BettypeID, 'Big Small/Odd Even' AS BettypeName
UNION SELECT 14 AS ChoiceId, 'Small Even'	AS ChoiceName, 5	 AS BettypeID, 'Big Small/Odd Even' AS BettypeName
UNION SELECT 15 AS ChoiceId, 'Gold'			AS ChoiceName, 6	 AS BettypeID, 'Five Element'		AS BettypeName
UNION SELECT 16 AS ChoiceId, 'Wood'			AS ChoiceName, 6	 AS BettypeID, 'Five Element'		AS BettypeName
UNION SELECT 17 AS ChoiceId, 'Water'		AS ChoiceName, 6	 AS BettypeID, 'Five Element'		AS BettypeName
UNION SELECT 18 AS ChoiceId, 'Fire'			AS ChoiceName, 6	 AS BettypeID, 'Five Element'		AS BettypeName
UNION SELECT 19 AS ChoiceId, 'Earth'		AS ChoiceName, 6	 AS BettypeID, 'Five Element'		AS BettypeName
UNION SELECT 20 AS ChoiceId, 'Star Odd'		AS ChoiceName, 7	 AS BettypeID, 'Star. Odd/Even'		AS BettypeName
UNION SELECT 21 AS ChoiceId, 'Star Even'	AS ChoiceName, 7	 AS BettypeID, 'Star. Odd/Even'		AS BettypeName
UNION SELECT 22 AS ChoiceId, 'Dragon'		AS ChoiceName, 8	 AS BettypeID, 'Dragon/Tiger'		AS BettypeName
UNION SELECT 23 AS ChoiceId, 'DT-Tie'		AS ChoiceName, 8	 AS BettypeID, 'Dragon/Tiger'		AS BettypeName
UNION SELECT 24 AS ChoiceId, 'Tiger'		AS ChoiceName, 8	 AS BettypeID, 'Dragon/Tiger'		AS BettypeName
UNION SELECT 25 AS ChoiceId, 'D. Big'		AS ChoiceName, 9	 AS BettypeID, 'Dragon. Big/Small'	AS BettypeName
UNION SELECT 26 AS ChoiceId, 'D. Small'		AS ChoiceName, 9	 AS BettypeID, 'Dragon. Big/Small'	AS BettypeName
UNION SELECT 27 AS ChoiceId, 'D. Odd'		AS ChoiceName, 10	 AS BettypeID, 'Dragon. Odd/Even'	AS BettypeName
UNION SELECT 28 AS ChoiceId, 'D. Even'		AS ChoiceName, 10	 AS BettypeID, 'Dragon. Odd/Even'	AS BettypeName
UNION SELECT 29 AS ChoiceId, 'T. Big'		AS ChoiceName, 11	 AS BettypeID, 'Tiger. Big/Small'	AS BettypeName
UNION SELECT 30 AS ChoiceId, 'T. Small'		AS ChoiceName, 11	 AS BettypeID, 'Tiger. Big/Small'	AS BettypeName
UNION SELECT 31 AS ChoiceId, 'T. Odd'		AS ChoiceName, 12	 AS BettypeID, 'Tiger. Odd/Even'	AS BettypeName
UNION SELECT 32 AS ChoiceId, 'T. Even'		AS ChoiceName, 12	 AS BettypeID, 'Tiger. Odd/Even'	AS BettypeName
GO
GO
GRANT SELECT ON [dbo].[View_KenoBettypeMapping] TO [bodbLicenseeNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[View_KenoBettypeMapping] TO [vnteam] 
GRANT SELECT ON [dbo].[View_KenoBettypeMapping] TO bodbAdminNet 


