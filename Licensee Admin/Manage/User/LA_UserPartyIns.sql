/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbLicenseeNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[LA_UserPartyIns] 
	@UserName				NVARCHAR(50)
	, @PartyName			NVARCHAR(50)	
AS
/*
	Created: 20150302@Florent
	Task : add permission for LA, User - Party	
	DB: DBLIC.bodb_licensee

	Revisions:
		- 20170912@Harper: Clear code [RedmineID: #82673] 

	Param's Explanation:
*/
BEGIN	
	DECLARE @userID INT, @PartyID INT

	SELECT @userID = UserID 
	FROM dbo.LA_User WITH (NOLOCK) 
	WHERE Username = @UserName

	SELECT @PartyID = PartyID
	FROM dbo.OAS_Party WITH (NOLOCK)
	WHERE PartyName = @PartyName AND PartyType = 1	

	IF ISNULL(@userID,0) = 0 OR ISNULL(@PartyID,0) = 0		
	BEGIN
		SELECT 'Error!!! Data error, please check :', @UserName AS '@UserName', @userID AS '@userID', @PartyName AS '@PartyName', @PartyID AS '@PartyID'
		RETURN
	END

	IF NOT EXISTS (SELECT 1 FROM dbo.LA_UserParty WITH (NOLOCK) WHERE UserID = @userID AND PartyID = @PartyID)
	BEGIN
		INSERT INTO LA_UserParty (UserID, PartyID, Modifydate, Modifier, StatusID)
		SELECT @userID, @PartyID, GETDATE(), @userID, 1
	END
	ELSE 
	BEGIN	
		SELECT 'Error!!! Permission exists, please check :', @UserName AS '@UserName', @userID AS '@userID', @PartyName AS '@PartyName', @PartyID AS '@PartyID'	
	END
END

