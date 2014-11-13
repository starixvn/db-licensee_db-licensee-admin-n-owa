USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[OAS_Party_SelBALicensees]   
	@ExcludeTest BIT = 1
AS  
  

/*  
 * Created by : 20131126@Francis 
 * Task  : Get all licensees (compatible with the new structure) for Sportbook Winloss report 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 	- 20141031@Florent: Apply new Structure Using SystemMapping
    - 20141105@Florent: fix get brand name of licensee
 * Param's Explanation:    
 * - @ExcludeTest: to exclude Spondemo (a test licensee)
 */  
 
BEGIN
	SET NOCOUNT ON  

	SELECT DISTINCT ci.FromParty AS PartyID
	,p.PartyName + CASE 
			WHEN ISNULL(pd.BrandName, '') = ''
				OR p.PartyName = pd.BrandName
				THEN ''
			ELSE ' (' + CAST(pd.BrandName AS VARCHAR(20)) + ')'
			END AS PartyName
    FROM dbo.OAS_ChargeInfo ci(NOLOCK)
	   INNER JOIN dbo.OAS_Party p(NOLOCK) ON ci.FromParty = p.PartyID
	   INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs(NOLOCK) ON ci.ChargeID = cs.ChargeID and cs.SystemID = 4
	   LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
    WHERE ci.ChargeType = 1
	    AND ci.ProductID = 3
	    AND (
		    (@ExcludeTest = 0)
		    OR (
			    @ExcludeTest = 1
			    AND ci.FromParty NOT IN (
				    SELECT p2.PartyID
				    FROM OAS_Party p2(NOLOCK)
				    WHERE p2.PartyName IN ('spondemo', 'Demo')
				    )
			    )
		    )
    ORDER BY p.PartyName + CASE 
			WHEN ISNULL(pd.BrandName, '') = ''
				OR p.PartyName = pd.BrandName
				THEN ''
			ELSE ' (' + CAST(pd.BrandName AS VARCHAR(20)) + ')'
			END ASC

END
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Party_SelBALicensees]TO [vnteam]
GRANT EXECUTE ON [dbo].[OAS_Party_SelBALicensees]TO bodbAdminNet