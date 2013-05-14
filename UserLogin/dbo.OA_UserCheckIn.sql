ALTER PROCEDURE [dbo].[OA_UserCheckIn]
	@CustID INT,
	@NetSessionID VARCHAR(30),
	@On_UserID INT OUTPUT,
	@IP VARCHAR(15) = ''
AS

/*
	Creator:  20111020@Henry
	Task: CheckIN
	DB: DB052.bodb_Licensee
	
	


*/

--if @@servername <> '5WRHH1S'--not kickout at local server for testing
update OA_OnUser with (ROWLOCK,UPDLOCK) SET IsKickedout=1 WHERE CustID = @CustID

	
insert into OA_OnUser
	(custid, NetSessionID, IsKickedout, IP)
values
	(@custid, @NetSessionid, 0, @IP)

SELECT @On_UserID = SCOPE_IDENTITY()


GO
GRANT EXECUTE ON [dbo].[OA_UserCheckIn] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OA_UserCheckIn] TO [vnteam]  