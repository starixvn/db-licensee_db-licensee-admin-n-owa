set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go
ALTER PROCEDURE [dbo].[OA_LicenseeProductGetAll]
AS
/*  
 * Created  : 20130108@Jim
 * Task  : Licensee Product & feature management
 * DB   : DB052.bodb02  
 * Revisions :  
	
 * Param's Explanation:    
 *  
 *  
 */  
BEGIN
	SELECT	l.LicenseeID
			,l.LicenseeName
			,ld.ProductID
			,p.ProductName
			,ld.Comm
			,ld.Winloss
			,l.IsAllowedMemberComm MemberComm
			,ld.EffectiveDate
	FROM bodb_licensee.dbo.Licensees l WITH (NOLOCK)
		LEFT JOIN bodb_licensee.dbo.LicenseeProduct3rd ld WITH (NOLOCK)
		ON ld.LicenseeID=l.LicenseeID
		LEFT JOIN bodb_licensee.dbo.Product3rd p WITH (NOLOCK)
		ON ld.ProductID=p.Productid
	ORDER BY l.LicenseeID ASC
END

GO
GRANT EXECUTE ON [dbo].[OA_LicenseeProductGetAll] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_LicenseeProductGetAll] TO [vnteam]



	