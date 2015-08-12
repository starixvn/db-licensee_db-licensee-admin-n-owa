ALTER PROCEDURE  [dbo].[OAS_SelBalanceUpDay]		
		
AS	
/*
Created: 20101210@Henry
Task : Get move bet day, balanceup day
DB: DB05.bodb02
Original: [Age_SelBalanceUpDay]

Revisions:
    
Param's Explanation:
*/

SET NOCOUNT ON
BEGIN
	DECLARE @BalanceUpDay smalldatetime, @MoveBetsDay smalldatetime
	SELECT 
		TOP 1 @BalanceUpDay = winlostdate
	FROM Bettrans WITH(NOLOCK)
	WHERE bettype = 20000 AND matchid = 0	AND custid = 3


	SELECT    @MoveBetsDay = @BalanceUpDay  
	

	SELECT @BalanceUpDay as BalanceUpDay, @MoveBetsDay as MoveBetsDay
END

GO
GRANT EXECUTE ON [dbo].[OAS_SelBalanceUpDay] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_SelBalanceUpDay] TO [vnteam]  
 