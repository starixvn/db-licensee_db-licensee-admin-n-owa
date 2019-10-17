/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_SummaryDel]
	@AccDate			DATE,
	@Environment		VARCHAR(10)
AS
/*	Header:
	Created: 20191017@Bruce
	Task : Clear data before regenerate licensee reconciliation summary
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20191017@Bruce: Create Sp [#112229]
*/
BEGIN
	SET NOCOUNT ON

	DELETE bodb_licenseeReport.dbo.rptLicenseeReconciliation
	WHERE AccDate = @AccDate AND Environment=@Environment
END
GO