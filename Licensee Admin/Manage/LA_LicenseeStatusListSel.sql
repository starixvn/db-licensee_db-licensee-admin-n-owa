/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

CREATE PROCEDURE [dbo].[LA_LicenseeStatusListSel]
AS
/*
	Created: 20170223@danny
	Task : Get list of terminated payers [#159296]
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20210823@Danny: filter licensee status from OIC [#159296]
	

	Params:
	Example:
		EXEC dbo.LA_LicenseeStatusListSel
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT  999 AS LicenseeStatusId, 'Unrecognized' AS LicenseeStatusName

	UNION ALL

	SELECT LicenseeStatusId, LicenseeStatusName
	FROM bodb_OIC.dbo.LicenseeStatus WITH(NOLOCK)
	ORDER BY LicenseeStatusId

END
GO