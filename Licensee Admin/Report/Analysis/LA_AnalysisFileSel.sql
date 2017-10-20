USE bodb_licensee
GO

ALTER PROC dbo.LA_AnalysisFileSel (
	@FileNames VARCHAR(4000) = '',
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
		- 20170919@Bruce: create SP
*/
BEGIN
	SET NOCOUNT ON

	IF @Fromdate IS NULL SET @Fromdate = '20000101'
	IF @ToDate IS NULL SET @ToDate = '20500101'
	IF @FileNames IS NULL SET @FileNames = ''

	SELECT *
	FROM dbo.LA_AnalysisFile f WITH(NOLOCK)
	WHERE f.FromDate >= @Fromdate AND f.ToDate <= @ToDate AND (
		ISNULL(@FileNames,'') = '' OR
		f.[Filename] IN (SELECT s.val FROM dbo.strSplit(@FileNames,',') s)
	)

END
GO

GRANT EXECUTE ON [dbo].LA_AnalysisFileSel TO [bodbLicenseeNet] AS [dbo]
go

GRANT EXECUTE ON [dbo].LA_AnalysisFileSel TO [bodbAdminNet] AS [dbo]
go

GRANT VIEW DEFINITION ON [dbo].LA_AnalysisFileSel TO [vnteam] AS [dbo]
go