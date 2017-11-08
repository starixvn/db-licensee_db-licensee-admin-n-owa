USE bodb_licensee
GO

ALTER PROC dbo.LA_AnalysisFileStatusSel (
	@Files AS XML
)
AS
/*
	Created: BRUCE
	Date: 2017-10-18
	Task: Licensee Analysis (support raw data) #redmind: https://nexdev.net/issues/78294
	DB: bodb_licensee

	Revisions:
		- 20171107@Bruce: create SP
*/
BEGIN
	SET NOCOUNT ON

	SELECT 
		t.c.value('@name',		'varchar(200)')		AS [Filename], 
		t.c.value('@partyids',	'varchar(4000)')	AS PartyIds,
		t.c.value('@codes',		'varchar(200)')		AS ProductCodes,
		t.c.value('@from',		'datetime')			AS FromDate,
		t.c.value('@to',		'datetime')			AS ToDate,
		t.c.value('@skin',		'bit')				AS IsSkinView,
		CAST(1 AS TINYINT) [Status] -- pending
	INTO #Files
	FROM @files.nodes('files/file') t(c)

	UPDATE fs SET [Status] = f.[Status]
	FROM dbo.LA_AnalysisFile f WITH(NOLOCK)
	INNER JOIN #Files fs ON f.FromDate = fs.FromDate
		AND f.IsSkinView = fs.IsSkinView
		AND f.PartyIds = fs.PartyIds
		AND f.ProductCodes = fs.ProductCodes
		AND f.ToDate = fs.ToDate

	UPDATE fs SET [Status] = 0 -- existed
	FROM dbo.LA_AnalysisFile f WITH(NOLOCK)
	INNER JOIN #Files fs ON f.[Filename] = fs.[Filename]

	SELECT * FROM #Files

	DROP TABLE #Files
END
GO

GRANT EXECUTE ON [dbo].LA_AnalysisFileStatusSel TO [bodbLicenseeNet] AS [dbo]
go

GRANT EXECUTE ON [dbo].LA_AnalysisFileStatusSel TO [bodbAdminNet] AS [dbo]
go

GRANT VIEW DEFINITION ON [dbo].LA_AnalysisFileStatusSel TO [vnteam] AS [dbo]
go