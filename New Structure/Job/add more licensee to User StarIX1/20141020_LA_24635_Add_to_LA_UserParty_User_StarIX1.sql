/*
    Author: FLorent.Nguyen
    Date : 2014-10-20
*/
USE bodb_licensee
GO

DECLARE @listParty AS TABLE (PartyID INT)
DECLARE @userStarIX INT

SET NOCOUNT ON
INSERT INTO @listParty
SELECT PartyID 
FROM OAS_Party WITH(NOLOCK)
WHERE PartyName IN 
		  (SELECT val 
			 FROM 
			 bodb02.dbo.strSplit('HAIFA,9bet,Royalebet,Bet2day,3star88,88Macao,67BET,HBOBet,Winner99,Mgm88,Ae88,M8bola,Allbetclub,AG,THBET,28bet,Honbet,9Club,iBET,BE7,Q8bola,DAYWIN',','))
      AND PartyType = 1
SELECT @userStarIX= UserID FROM LA_User WHERE Username = 'StarIX1'

SET NOCOUNT OFF

INSERT INTO LA_UserParty (UserID,PartyID,Modifydate,Modifier, StatusID)
SELECT @userStarIX,PartyID,GETDATE(),@userStarIX,1
FROM @listParty 
WHERE PartyID NOT IN (SELECT up.PartyID 
				    FROM LA_UserParty up WITH(NOLOCK)
					   INNER JOIN @listParty l ON up.PartyID = l.PartyID AND up.UserID = @userStarIX)
GO
