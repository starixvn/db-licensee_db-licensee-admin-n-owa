/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[OAS_Users_CheckIn]  
	@CustID			INT,
	@NetSessionID	VARCHAR(30),
	@On_UserID		INT	= 0 OUTPUT,
	@IP				VARCHAR(15) = ''
AS

/*
	Created by: [20111512@Kos]
	Task: check in user
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20190510@Percy: Move SP to DBCUST.bodb_Licensee [RedmineID: #103658]
	
	Param's Explanation:
		- @CustID: Customer ID
		- @NetSessionID: Net session ID
		- @On_UserID: User ID
		- @IP: IP address
*/

BEGIN
	SET NOCOUNT ON   

	UPDATE dbo.OAS_OnUser WITH (ROWLOCK, UPDLOCK)
	SET IsKickedout = 1
	WHERE CustID = @CustID

	INSERT INTO dbo.OAS_OnUser
		(custid, NetSessionID, IsKickedout, IP)
	VALUES
		(@custid, @NetSessionid, 0, @IP)
  
	SELECT @On_UserID = SCOPE_IDENTITY()
END
GO