USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[OAS_3rdProductGetPartys]
@ProductID INT
AS  
  
/*  
 * Created by : 20150320@Winnie
 * Task  : Get all licensees (compatible with the new structure) for 3rd product Winloss report 
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
					ELSE p.PartyName + CASE WHEN ISNULL(pd.BrandName,'') = '' OR p.PartyName = pd.BrandName THEN ''
									    ELSE ' ('+CAST(pd.BrandName AS VARCHAR(20) )+')'
								    END
				END AS PartyName
		FROM dbo.OAS_ChargeInfo ci (NOLOCK) 
			INNER JOIN dbo.OAS_Party p (NOLOCK) ON ci.FromParty = p.PartyID
			INNER JOIN dbo.OAS_Party p1 (NOLOCK) ON ci.toParty = p1.PartyID
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 4
			LEFT JOIN dbo.OAS_PartyDetail pd (NOLOCK) ON p.PartyID = pd.PartyID
			LEFT JOIN dbo.LicenseeReseller lr WITH (NOLOCK) ON p.OldRefID=lr.LicenseeID
			LEFT JOIN dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID=r.ResellerID
		WHERE ci.ProductID = @ProductID
		and p.PartyType=1						
		ORDER BY PartyName ASC
END

GO
GRANT VIEW DEFINITION ON [dbo].[OAS_3rdProductGetPartys] TO [vnteam] 
GRANT EXECUTE ON [dbo].[OAS_3rdProductGetPartys] TO bodbAdminNet 