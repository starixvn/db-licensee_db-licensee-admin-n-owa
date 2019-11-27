/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_UserCheckIn]
	@CustID INT,
	@NetSessionID VARCHAR(30),
	@On_UserID INT OUTPUT,
	@IP VARCHAR(15) = ''
AS

/*
	Creator: 20140820@Florent
	Task: CheckIN
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20140820@Florent: Initialize SP
		- 20191127@Bruce: Only update non-kicked out records [#119538]
*/

SET NOCOUNT ON
BEGIN
    UPDATE LA_OnUser with (ROWLOCK,UPDLOCK) SET IsKickedout = 1 WHERE CustID = @CustID AND IsKickedout = 0
    	
    INSERT INTO dbo.LA_OnUser
	    (custid, NetSessionID, IsKickedout, IP)
    VALUES
	    (@custid, @NetSessionid, 0, @IP)

    SELECT @On_UserID = SCOPE_IDENTITY()
END
GO