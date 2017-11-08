USE bodb_licensee
GO

ALTER PROC dbo.LA_AnalysisFileIns
	@Files AS XML
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

	INSERT INTO dbo.LA_AnalysisFile(Filename, PartyIds, ProductCodes,FromDate,ToDate,IsSkinView, [Status])
	SELECT 
		t.c.value('@name',		'varchar(200)'), 
		t.c.value('@partyids',	'varchar(4000)'),
		t.c.value('@codes',		'varchar(200)'),
		t.c.value('@from',		'datetime'),
		t.c.value('@to',		'datetime'),
		t.c.value('@skin',		'bit'),
		1 -- pending
	FROM @files.nodes('files/file') t(c)

END
GO

GRANT EXECUTE ON [dbo].LA_AnalysisFileIns TO [bodbLicenseeNet] AS [dbo]
go

GRANT EXECUTE ON [dbo].LA_AnalysisFileIns TO [bodbAdminNet] AS [dbo]
go

GRANT VIEW DEFINITION ON [dbo].LA_AnalysisFileIns TO [vnteam] AS [dbo]
go