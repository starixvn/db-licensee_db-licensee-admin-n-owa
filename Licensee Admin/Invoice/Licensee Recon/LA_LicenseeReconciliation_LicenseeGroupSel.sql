/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_LicenseeGroupSel_UAT3]
	@GroupId INT 
AS
/*	Header:
	Task : Get licensee group for licensee recon
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20191004@Bruce: create sp [#120220]
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @pathCode VARCHAR(10) =  '%/' + CAST(@GroupId AS VARCHAR(5)) + '/%'

	SELECT d.PartyId,d.LicenseeCode
	FROM dbo.LA_CombinedGroupAssignment a WITH(NOLOCK)
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.PartyID=a.PartyId
	WHERE GroupId IN (
		SELECT c.GroupId from dbo.LA_CombinedGroup c WITH(NOLOCK) WHERE c.PathCode LIKE @pathCode OR c.GroupId = @GroupId
	) AND ISNULL(d.LicenseeCode,'') <> ''
END
GO