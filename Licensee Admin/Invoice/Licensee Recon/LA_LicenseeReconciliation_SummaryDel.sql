/*<info serverAlias="DBLIC-bodb_licenseeReport" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licenseeReport
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_SummaryDel]
	@AccDate		DATE,
	@Environment	VARCHAR(10),
	@ForceDelete	BIT = 0
AS
/*	Header:
	Created: 20191017@Bruce
	Task : Clear data before regenerate licensee reconciliation summary
	DB: DBLIC.bodb_licenseeReport

	Revisions: 
		- 20191017@Bruce: Create Sp [#122229]
		- 20240401@Danny: Change meta data [#203267]
*/
BEGIN
	SET NOCOUNT ON

	DELETE dbo.rptLicenseeReconciliation
	WHERE Environment=@Environment
		AND AccDate = @AccDate
		AND (@ForceDelete = 1 OR @Environment <> 'PRO' OR @AccDate > '20190930')
		-- We manually inserted data for August and Septemper 2019 on PRO so they should be locked from deleting
END
GO