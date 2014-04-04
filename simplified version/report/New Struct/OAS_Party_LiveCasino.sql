USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Party_LiveCasino]    Script Date: 01/04/2014 5:27:27 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[OAS_Party_LiveCasino]
AS  
  
/*  
 * Created by : 20140328@Florent 
 * Task  : Get all licensees (compatible with the new structure) for Live Casino Winloss report 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
	- 20140404: hard code for Boping
 	
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
		WHERE ci.ProductID = 4
		and p.PartyType=1						
		ORDER BY PartyName ASC
END
GO
GRANT EXECUTE ON [dbo].[OAS_Party_LiveCasino] TO [bodbLicenseeNet] 
GRANT EXECUTE ON [dbo].[OAS_Party_LiveCasino] TO bodbAdminNet 
GRANT VIEW DEFINITION ON [dbo].[OAS_Party_LiveCasino] TO [vnteam] 


