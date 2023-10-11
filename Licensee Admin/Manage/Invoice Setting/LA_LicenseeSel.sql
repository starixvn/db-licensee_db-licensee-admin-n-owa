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
		- 20231011@Danny: return LaunchedDate and the last day of previous billing cycle [#194890]

	 Params:

	 Explannation: EXEC LA_LicenseeSel
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @MaxInvoiceDate DATE
	SELECT  @MaxInvoiceDate = MAX(InvoiceDate) FROM LA_InvoiceHeader WITH(NOLOCK) WHERE InvoiceType = 1

	; WITH t AS
	(
		SELECT FromParty AS PartyID, MIN(FromDate) AS AffectedDate
		FROM OAS_ChargeInfo ci WITH(NOLOCK)
		GROUP BY FromParty
	)
	SELECT  t.PartyID, t.AffectedDate, op.LaunchDate, @MaxInvoiceDate MaxInvoiceDate
	FROM t 
	LEFT JOIN OAS_PartyDetail op WITH(NOLOCK) ON t.PartyID = op.PartyID
END
GO