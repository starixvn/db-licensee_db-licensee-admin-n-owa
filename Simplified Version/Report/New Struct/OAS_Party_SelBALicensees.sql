USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Party_SelBALicensees]    Script Date: 4/2/2014 11:11:18  ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****** Object:  Stored Procedure dbo.OAS_Party_SelBALicensees    Script Date: 12/31/2013 10:38:18  ******/





ALTER PROCEDURE [dbo].[OAS_Party_SelBALicensees]   
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

	SELECT DISTINCT ci.FromParty AS PartyID, p.PartyName AS PartyName
	FROM OAS_ChargeInfo ci (NOLOCK) 
	INNER JOIN OAS_Party p (NOLOCK) ON ci.FromParty = p.PartyID
	WHERE ci.ChargeType = 1
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