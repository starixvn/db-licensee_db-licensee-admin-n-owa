/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_SporttypeListSel](
	@ProductCodes VARCHAR(500)
)
AS

/*
	Created: Bruce.Bui
	Date: 2016-01-13
	Task: Get sport types by given products
	DB: DBEXT.bodb02
	
	Revisions:
		- 20170816@Percy: Change data type of Sporttype [RedmineID: #73545]
		- 20200619@Happy: Increase the length of @ProductCode params [#128570]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @Products TABLE(Code VARCHAR(10))
	DECLARE @Sporttypes TABLE(Sporttype SMALLINT, SportName NVARCHAR(50), ProductCode VARCHAR(10))

	INSERT INTO @Products(Code)
	(
		SELECT val FROM bodb02.dbo.strSplit(@ProductCodes, ',')
	)

	IF EXISTS (SELECT 1 FROM @Products WHERE Code = 'SB')
	BEGIN
		INSERT INTO @Sporttypes(Sporttype,SportName, ProductCode)
		(
			SELECT Sporttype,SportName, 'SB'
			FROM Sports WITH (NOLOCK)
			WHERE sporttype <= 99
		)
	END

	IF EXISTS (SELECT 1 FROM @Products WHERE Code = 'VS')
	BEGIN
		INSERT INTO @Sporttypes(Sporttype,SportName, ProductCode)
		(
			SELECT Sporttype,SportName, 'VS'
			FROM Sports WITH (NOLOCK)
			WHERE sporttype BETWEEN 180 AND 199
		)
	END

	IF EXISTS (SELECT 1 FROM @Products WHERE Code = 'CS')
	BEGIN
		INSERT INTO @Sporttypes(Sporttype,SportName, ProductCode)
		(
			SELECT Sporttype,SportName, 'CS'
			FROM Sports WITH (NOLOCK)
			WHERE sporttype IN (208,209,210)
		)
	END

	SELECT Sporttype,SportName, ProductCode FROM @Sporttypes
END
GO