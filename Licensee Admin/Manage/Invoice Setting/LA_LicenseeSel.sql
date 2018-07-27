/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeSel] 
AS
/*  
	 Created: 20180727@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180727@Parsons: get licensee info [#94282]
	 Params:

	 Explannation: EXEC LA_LicenseeSel
*/

BEGIN
	SET NOCOUNT ON
	
	SELECT p.PartyID, l.*
	FROM Licensees l WITH(NOLOCK)
		INNER JOIN OAS_Party p WITH(NOLOCK) ON l.LicenseeID = p.OldRefID
	WHERE p.PartyType IN (1, 5)
END
GO