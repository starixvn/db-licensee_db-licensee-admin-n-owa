USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Party_SelBALicensees]    Script Date: 02/04/2014 11:02:52 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[OAS_Party_SelBALicensees]   
	@FromDate SMALLDATETIME,
	@ToDate   SMALLDATETIME,
	@ExcludeTest BIT = 1
AS  
  
/*  
 * Created by : 20131126@Francis 
 * Task  : Get all licensees (compatible with the new structure) for Sportbook Winloss report 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 	
 * Param's Explanation:    
 * - @ExcludeTest: to exclude Spondemo (a test licensee)
 */  
 
BEGIN
	SET NOCOUNT ON  
	SELECT @Fromdate=ltrim(rtrim(@Fromdate)),@Todate=ltrim(rtrim(@Todate))

	SELECT DISTINCT ci.FromParty AS PartyID, p.PartyName AS PartyName
	FROM OAS_ChargeInfo ci (NOLOCK) 
	INNER JOIN OAS_Party p (NOLOCK) ON ci.FromParty = p.PartyID
	WHERE (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR 
		  @ToDate BETWEEN ci.FromDate AND ci.ToDate)
		  AND ci.ChargeType = 1
		  AND ci.ProductID = 3
		  AND ((@ExcludeTest = 0) OR (@ExcludeTest = 1 AND ci.FromParty NOT IN (SELECT p2.PartyID 
																				FROM OAS_Party p2 (NOLOCK) 
																				WHERE p2.PartyName IN ('spondemo','Demo'))))	  
	ORDER BY p.PartyName ASC
END
GO
GRANT EXECUTE ON [dbo].[OAS_Party_SelBALicensees] TO [bodbLicenseeNet] 
GRANT EXECUTE ON [dbo].[OAS_Party_SelBALicensees] TO bodbAdminNet 
GRANT VIEW DEFINITION ON [dbo].[OAS_Party_SelBALicensees] TO [vnteam] 