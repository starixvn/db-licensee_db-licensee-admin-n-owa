/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet,bodbLicenseeNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE dbo.[LA_AnalysisFileUpd]
	@FileName	VARCHAR(200),
	@Status		TINYINT
AS
/*
	Created: BRUCE
	Date: 2017-10-18
	Task: Licensee Analysis (support raw data) #redmind: https://nexdev.net/issues/78294
	DB: DBCUST.bodb_licensee

	Revisions:
		- 20170919@Bruce: create SP [RedmineID: #78294]
*/
BEGIN
	SET NOCOUNT ON

	UPDATE dbo.LA_AnalysisFile WITH(ROWLOCK, UPDLOCK)
	SET [Status] = @Status
	WHERE [Filename] = @FileName
END
GO