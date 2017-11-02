CREATE PROCEDURE [dbo].[LA_CumulativeSettlementHistorySel]
	@FromDate	DATE,
	@ToDate		DATE
AS  
/*
Header:  
	Created: 2017.11.02 - Bruce.bui
	Task : Select rebate group info
	DB: DB052.bodb_Licensee  
     
Revisions:   
Example:  
	USE bodb_licensee   
	EXEC [LA_CumulativeSettlementHistorySel] '20170101', '20170131'
*/  
BEGIN  
	SET NOCOUNT ON  
   
	SELECT s.SettlementId, s.SettlementDate, p.PartyName
	FROM dbo.LA_CummulativeSettlement s WITH(NOLOCK)
	INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID=s.PartyId
	WHERE s.SettlementDate BETWEEN @FromDate AND @ToDate
	ORDER BY s.CreatedDate DESC
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_CumulativeSettlementHistorySel] TO [vnteam]
GO

GRANT EXECUTE ON [dbo].[LA_CumulativeSettlementHistorySel] TO bodbAdminNet
GO