/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO 

ALTER PROCEDURE [dbo].[OAS_Users_ReCheckIn]
	@On_UserID		INT,
	@IsKickedOut	BIT = 0 OUTPUT
AS

/*
	Created by: [20111512@Kos]
	Task: Recheck in user
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20190510@Percy: Move SP to DBCUST.bodb_Licensee [RedmineID: #103658]
	
	Param's Explanation:
		- @On_UserID : User ID
		- @IsKickedOut : Is kicked out or not (output)
*/

BEGIN
	SET NOCOUNT ON

	IF EXISTS (SELECT 1 FROM dbo.OAS_OnUser WITH (NOLOCK) WHERE On_UserID = @On_UserID AND isKickedOut = 1)
	BEGIN
		SELECT @IsKickedOut = 1
	END
	ELSE
	BEGIN
		 SELECT @IsKickedOut = 0

		 UPDATE dbo.OAS_OnUser WITH (ROWLOCK, UPDLOCK)
		 SET reload_time = GETDATE()
		 WHERE on_userid = @On_UserID

		 IF @@ROWCOUNT = 0
			SELECT @IsKickedOut = 1
	END
END
GO