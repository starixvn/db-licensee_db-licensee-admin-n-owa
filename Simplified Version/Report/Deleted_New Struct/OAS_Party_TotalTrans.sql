USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[OAS_Party_TotalTrans]   
	@FromDate SMALLDATETIME,
	@ToDate   SMALLDATETIME,	
	@ExcludeTest BIT = 1
AS  
  
/*  
 * Created by : 20131126@Francis 
 * Task  : Get all licensees (compatible with the new structure) for Total Trans report 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 	
 * Param's Explanation:    
 *  - @ExcludeTest: to exclude Spondemo (a test licensee)
 */  
 
BEGIN
	SET NOCOUNT ON  
	SELECT @Fromdate=ltrim(rtrim(@Fromdate)),@Todate=ltrim(rtrim(@Todate))

	SELECT DISTINCT ci.ChargeID, ci.FromParty AS PartyID, p.PartyName AS PartyName, ci.ParentChargeID
	FROM OAS_ChargeInfo ci (NOLOCK) 
	INNER JOIN OAS_Party p (NOLOCK) ON ci.FromParty = p.PartyID
	WHERE (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR 
		  @ToDate BETWEEN ci.FromDate AND ci.ToDate)
		  AND ci.ChargeType = 2
		  AND ci.ProductID = 0
          AND ci.ToParty IN (SELECT p1.PartyID 
							 FROM OAS_Party p1 (NOLOCK) 
							 WHERE p1.PartyName IN ('Oneworks','BCH','LDL')
							 )
		  AND ((@ExcludeTest = 0) OR 
				(@ExcludeTest = 1 AND ci.FromParty NOT IN (SELECT p2.PartyID 
															FROM OAS_Party p2 (NOLOCK) 
															WHERE p2.PartyName IN ('spondemo','Demo')))
				)
		  AND ci.MinTrans = 0
	ORDER BY ci.ParentChargeID ASC
END

GO
GRANT EXECUTE ON [dbo].[OAS_Party_TotalTrans] TO [bodbLicenseeNet] 
GRANT EXECUTE ON [dbo].[OAS_Party_TotalTrans] TO bodbAdminNet 
GRANT VIEW DEFINITION ON [dbo].[OAS_Party_TotalTrans] TO [vnteam] 
