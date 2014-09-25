USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Party_AGCasino]    Script Date: 25/09/2014 15:06:25 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[OAS_Party_AGCasino]
AS  
  
/*  
 * Created by : 20140925@Florent 
 * Task  : Get all licensees (compatible with the new structure) for AGCasino Winloss report 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 	
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	SET NOCOUNT ON  
	SELECT DISTINCT case when p1.PartyName='Boping' then p1.PartyID else  ci.FromParty end AS PartyID,
				CASE 
					WHEN p.PartyName='IBC' THEN r.ResellerName
					WHEN p.PartyName='18bb' THEN r.ResellerName
					WHEN p1.PartyName='Boping' THEN p1.PartyName
					ELSE p.PartyName 
				END AS PartyName
		FROM OAS_ChargeInfo ci (NOLOCK) 
			INNER JOIN OAS_Party p (NOLOCK) ON ci.FromParty = p.PartyID
			INNER JOIN OAS_Party p1 (NOLOCK) ON ci.toParty = p1.PartyID
			LEFT JOIN dbo.LicenseeReseller lr WITH (NOLOCK) ON p.OldRefID=lr.LicenseeID
			LEFT JOIN dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID=r.ResellerID
		WHERE ci.ProductID = 10
		and p.PartyType=1						
		ORDER BY PartyName ASC
END

GO
GRANT EXECUTE ON [dbo].[OAS_Party_AGCasino] TO [bodbLicenseeNet] 
GRANT VIEW DEFINITION ON [dbo].[OAS_Party_AGCasino] TO [vnteam] 
GRANT EXECUTE ON [dbo].[OAS_Party_AGCasino] TO bodbAdminNet 
