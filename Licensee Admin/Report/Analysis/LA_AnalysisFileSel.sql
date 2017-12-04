/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet,bodbLicenseeNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.[LA_AnalysisFileSel] (
	@FileName VARCHAR(200) = '',
	@Fromdate DATETIME = NULL,  
	@ToDate DATETIME = NULL
)
AS
/*
	Created: BRUCE
	Date: 2017-10-18
	Task: Licensee Analysis (support raw data) #redmind: https://nexdev.net/issues/78294
	DB: bodb_licensee

	Revisions:
		- 20170919@Bruce: create SP [RedmineID: #78294]
*/
BEGIN
	SET NOCOUNT ON

	IF @Fromdate IS NULL SET @Fromdate = '20000101'
	IF @ToDate IS NULL SET @ToDate = '20500101'

	SELECT FileId, PartyIds, ProductCodes, Filename, FromDate, ToDate, [Status], IsSkinView
	FROM dbo.LA_AnalysisFile f WITH(NOLOCK)
	WHERE f.FromDate >= @Fromdate AND f.ToDate <= @ToDate AND (
		ISNULL(@FileName,'') = '' OR f.[Filename] LIKE @FileName ESCAPE '\'
	)

END
GO

GRANT EXECUTE ON [dbo].[LA_AnalysisFileSel] TO [bodbLicenseeNet] AS [dbo]
go

GRANT EXECUTE ON [dbo].[LA_AnalysisFileSel] TO [bodbAdminNet] AS [dbo]
go

GRANT VIEW DEFINITION ON [dbo].[LA_AnalysisFileSel] TO [vnteam] AS [dbo]
go