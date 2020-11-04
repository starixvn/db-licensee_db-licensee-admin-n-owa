/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeSel] 
AS
/*  
	 Created: 20180727@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180727@Parsons: get licensee info [#94282]
		- 20201104@Parsons: Group Min Fee & Discount Group - Enhance to check the launch date of Licensee [#144502]
	 
	 Params:

	 Explannation: EXEC LA_LicenseeSel
*/

BEGIN
	SET NOCOUNT ON
	
	SELECT p.PartyID, MIN(l.EffectiveDate) AS AffectedDate
	FROM OAS_Party p WITH(NOLOCK)
		INNER JOIN LicenseeProduct3rd l WITH(NOLOCK) ON l.LicenseeID = p.OldRefID
	WHERE p.PartyType IN (1, 5)
	GROUP BY p.PartyID
END
GO