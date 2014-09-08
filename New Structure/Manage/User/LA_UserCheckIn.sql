USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_UserCheckIn]    Script Date: 9/8/2014 4:58:09 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_UserCheckIn]
	@CustID INT,
	@NetSessionID VARCHAR(30),
	@On_UserID INT OUTPUT,
	@IP VARCHAR(15) = ''
AS

/*
	Creator:  20140820@Florent
	Task: CheckIN
	DB: DB052.bodb_Licensee	
*/

SET NOCOUNT ON
BEGIN
    UPDATE LA_OnUser with (ROWLOCK,UPDLOCK) SET IsKickedout=1 WHERE CustID = @CustID
    	
    INSERT INTO dbo.LA_OnUser
	    (custid, NetSessionID, IsKickedout, IP)
    VALUES
	    (@custid, @NetSessionid, 0, @IP)

    SELECT @On_UserID = SCOPE_IDENTITY()
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_UserCheckIn] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_UserCheckIn] TO bodbAdminNet 

