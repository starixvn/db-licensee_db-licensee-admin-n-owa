/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet,bodbLicenseeNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_AnalysisFileIns]
	@Files XML
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