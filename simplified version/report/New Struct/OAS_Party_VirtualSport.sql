USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Party_VirtualSport]    Script Date: 01/04/2014 5:28:53 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[OAS_Party_VirtualSport]
AS  
  
/*  
 * Created by : 20140328@Florent 
 * Task  : Get all licensees (compatible with the new structure) for VirtualSport Winloss report 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 	
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	SET NOCOUNT ON  
	SELECT DISTINCT ci.FromParty AS PartyID,
				CASE 
					WHEN p.PartyName='IBC' THEN r.ResellerName
					WHEN p.PartyName='18bb' THEN r.ResellerName
					ELSE p.PartyName 
				END AS PartyName
		FROM OAS_ChargeInfo ci (NOLOCK) 
			INNER JOIN OAS_Party p (NOLOCK) ON ci.FromParty = p.PartyID
			LEFT JOIN dbo.LicenseeReseller lr WITH (NOLOCK) ON p.OldRefID=lr.LicenseeID
			LEFT JOIN dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID=r.ResellerID
		WHERE ci.ProductID = 5
		and p.PartyType=1						
		ORDER BY ci.FromParty ASC
END

GO
GRANT EXECUTE ON [dbo].[OAS_Party_VirtualSport] TO [bodbLicenseeNet] 
GRANT EXECUTE ON [dbo].[OAS_Party_VirtualSport] TO bodbAdminNet 
GRANT VIEW DEFINITION ON [dbo].[OAS_Party_VirtualSport] TO [vnteam] 
