USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Party_Sportbook]    Script Date: 4/2/2014 11:04:37  ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****** Object:  Stored Procedure dbo.OAS_Party_Sportbook    Script Date: 12/31/2013 10:38:18  ******/




ALTER PROCEDURE [dbo].[OAS_Party_Sportbook]   
AS  
  
/*  
 * Created by : 20131126@Francis 
 * Task  : Get all licensees (compatible with the new structure) for Sportbook Winloss report 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 	- 20141020@Florent: fix get only ONEWorks's Licensee and group all Boping's licensee to only row Boping
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	SET NOCOUNT ON 

	SELECT DISTINCT CASE 
				    WHEN p1.PartyName='Boping' THEN p1.PartyID 
				    ELSE ci.FromParty 
				 END AS PartyID,
				CASE 
					WHEN p.PartyName='IBC' THEN r.ResellerName
					WHEN p.PartyName='18bb' THEN r.ResellerName
					WHEN p1.PartyName='Boping' THEN p1.PartyName
					ELSE p.PartyName 
				END AS PartyName , ci.MinFee, e.Code AS CurrencyCode
	FROM OAS_ChargeInfo ci (NOLOCK) 
	INNER JOIN OAS_Party p (NOLOCK) ON ci.FromParty = p.PartyID
	INNER JOIN OAS_Party p1 (NOLOCK) ON ci.ToParty = p1.PartyID
	INNER JOIN bodb02.dbo.Exchange e (NOLOCK) ON ci.MinFeeCurrencyID = e.exchangeid
	LEFT JOIN dbo.LicenseeReseller lr WITH (NOLOCK) ON p.OldRefID=lr.LicenseeID
			LEFT JOIN dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID=r.ResellerID
	WHERE ci.ChargeType = 1
		  AND ci.ProductID = 0 AND p.PartyType = 1AND p1.PartyName !='Boping'
	ORDER BY CASE 
			 WHEN p.PartyName='IBC' THEN r.ResellerName
			 WHEN p.PartyName='18bb' THEN r.ResellerName
			 WHEN p1.PartyName='Boping' THEN p1.PartyName
			 ELSE p.PartyName 
		    END ASC
END
GO
GRANT EXECUTE ON [dbo].[OAS_Party_Sportbook] TO [bodbLicenseeNet] 
GRANT EXECUTE ON [dbo].[OAS_Party_Sportbook] TO bodbAdminNet 
GRANT VIEW DEFINITION ON [dbo].[OAS_Party_Sportbook] TO [vnteam] 


