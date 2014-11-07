USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[OAS_Party_Sportbook]   
AS  
  
/*  
 * Created by : 20131126@Francis 
 * Task  : Get all licensees (compatible with the new structure) for Sportbook Winloss report 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 	- 20141020@Florent: fix get only ONEWorks's Licensee 
	- 20141031@Florent: Apply new Structure Using SystemMapping
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	SET NOCOUNT ON 

	SELECT DISTINCT CASE 
				    WHEN p1.PartyName = 'Boping' THEN p1.PartyID 
				    ELSE ci.FromParty 
				 END AS PartyID,
				CASE 
					WHEN p.PartyName = 'IBC' THEN r.ResellerName
					WHEN p.PartyName = '18bb' THEN r.ResellerName
					WHEN p1.PartyName = 'Boping' THEN p1.PartyName
					ELSE p.PartyName 
				END AS PartyName , cm.MinFee, e.Code AS CurrencyCode
	FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK) 
		INNER JOIN dbo.LA_ChargeInfo_MinFee cm WITH (NOLOCK) ON ci.ChargeID = cm.ChargeID
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 4
		INNER JOIN OAS_Party p WITH(NOLOCK) ON ci.FromParty = p.PartyID
		INNER JOIN OAS_Party p1 WITH(NOLOCK) ON ci.ToParty = p1.PartyID
		INNER JOIN bodb02.dbo.Exchange e WITH(NOLOCK) ON cm.MinFeeCurrencyID = e.exchangeid	
		LEFT JOIN dbo.LicenseeReseller lr WITH (NOLOCK) ON p.OldRefID=lr.LicenseeID
		LEFT JOIN dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID=r.ResellerID
	WHERE ci.ChargeType = 1
		  AND ci.ProductID = 0 
		  AND p.PartyType = 1 
		  AND p1.PartyName != 'Boping'
	ORDER BY CASE 
			 WHEN p.PartyName = 'IBC' THEN r.ResellerName
			 WHEN p.PartyName = '18bb' THEN r.ResellerName
			 WHEN p1.PartyName = 'Boping' THEN p1.PartyName
			 ELSE p.PartyName 
		    END ASC
END

GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Party_Sportbook] TO [vnteam] 
GRANT EXECUTE ON [dbo].[OAS_Party_Sportbook] TO bodbAdminNet 