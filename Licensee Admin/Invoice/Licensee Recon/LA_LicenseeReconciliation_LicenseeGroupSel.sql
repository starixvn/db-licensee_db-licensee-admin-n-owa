/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_LicenseeGroupSel]
	@GroupId INT,
	@ReportMonth	DATE
AS
/*	Header:
	Task : Get licensee group for licensee recon
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20191004@Bruce: create sp [#120220]
		- 20210323@Percy: Support duo base currency [RedmineID: #152089]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @LastDayOfMonth DATE = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, 0, @ReportMonth) + 1, 0))

	DECLARE @pathCode VARCHAR(10) =  '%/' + CAST(@GroupId AS VARCHAR(5)) + '/%'

	SELECT bc.PartyId,bc.LicenseeCode
	FROM dbo.LA_CombinedGroupAssignment a WITH(NOLOCK)
	INNER JOIN dbo.OAS_PartyBaseCurrency bc WITH(NOLOCK) ON bc.PartyID=a.PartyId
	WHERE GroupId IN (
		SELECT c.GroupId from dbo.LA_CombinedGroup c WITH(NOLOCK) WHERE c.PathCode LIKE @pathCode OR c.GroupId = @GroupId
	)
		AND ISNULL(bc.LicenseeCode,'') <> ''
		AND @LastDayOfMonth BETWEEN bc.FromDate AND bc.ToDate
END
GO