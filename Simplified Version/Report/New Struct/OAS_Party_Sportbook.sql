USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Party_Sportbook]    Script Date: 02/04/2014 11:01:20 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[OAS_Party_Sportbook]   
	@FromDate SMALLDATETIME,
	@ToDate   SMALLDATETIME	
AS  
  
/*  
 * Created by : 20131126@Francis 
 * Task  : Get all licensees (compatible with the new structure) for Sportbook Winloss report 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 	
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	SET NOCOUNT ON  
	SELECT @Fromdate=ltrim(rtrim(@Fromdate)),@Todate=ltrim(rtrim(@Todate))

	SELECT DISTINCT ci.FromParty AS PartyID, p.PartyName AS PartyName, ci.MinFee, e.Code AS CurrencyCode
	FROM OAS_ChargeInfo ci (NOLOCK) 
	INNER JOIN OAS_Party p (NOLOCK) ON ci.FromParty = p.PartyID
	INNER JOIN bodb02.dbo.Exchange e (NOLOCK) ON ci.MinFeeCurrencyID = e.exchangeid
	WHERE (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR 
		  @ToDate BETWEEN ci.FromDate AND ci.ToDate)
		  AND ci.ChargeType = 1
		  AND ci.ProductID = 0	  
	ORDER BY p.PartyName ASC
END
GO
GRANT EXECUTE ON [dbo].[OAS_Party_Sportbook] TO [bodbLicenseeNet] 
GRANT EXECUTE ON [dbo].[OAS_Party_Sportbook] TO bodbAdminNet 
GRANT VIEW DEFINITION ON [dbo].[OAS_Party_Sportbook] TO [vnteam] 


