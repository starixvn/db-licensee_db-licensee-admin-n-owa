/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[OAS_Party_NumberGame]
AS

/*
	Created by: 20140328@Florent
	Task: Get all licensees (compatible with the new structure) for NumberGame Winloss report
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20141031@Florent: Apply new Structure Using SystemMapping
		- 20141105@Florent: fix get brand name of licensee
 	
	Param's Explanation:
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
		FROM OAS_ChargeInfo ci (NOLOCK) 
			INNER JOIN OAS_Party p (NOLOCK) ON ci.FromParty = p.PartyID
			INNER JOIN OAS_Party p1 (NOLOCK) ON ci.toParty = p1.PartyID
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping (NOLOCK) cs ON ci.ChargeID = cs.ChargeID
			LEFT JOIN dbo.OAS_PartyDetail pd (NOLOCK) ON p.PartyID = pd.PartyID
			LEFT JOIN dbo.LicenseeReseller lr WITH (NOLOCK) ON p.OldRefID=lr.LicenseeID
			LEFT JOIN dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID=r.ResellerID
		WHERE ci.ProductID = 2
			   AND p.PartyType=1
			   AND cs.SystemID = 4
		ORDER BY PartyName asc 
END
GO