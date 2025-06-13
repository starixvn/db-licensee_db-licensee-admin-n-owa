/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20250613@Eddie
	DB: DBCUST.bodb_licensee
	Task: Add new key on Manage System Settings function [RedmineID: #228195]
*/
USE bodb_licensee
GO

DECLARE @KeyName VARCHAR(100) = 'SettlementReport_Templates'
	  , @KValue  VARCHAR(4000)

DECLARE @KeySetting TABLE ( Template TINYINT, ProductPrefix VARCHAR(10), SPtype TINYINT )

INSERT INTO @KeySetting (Template, ProductPrefix, SPtype)
SELECT t.Template, t.ProductPrefix, t.SPtype
FROM (
		VALUES (1, 'SB'		, 1)
			  ,(2, 'BA'		, 1)
			  ,(3, 'AGC'	, 2)
			  ,(3, 'SG'		, 2)
			  ,(3, 'PP'		, 2)
			  ,(3, 'VGA'	, 2)
			  ,(4, 'CC'		, 1)
			  ,(4, 'AB'		, 1)
			  ,(4, 'SXG'	, 1)
			  ,(4, 'PGS'	, 1)
			  ,(4, 'MGRNG'	, 1)
			  ,(4, 'L22'	, 1)
			  ,(4, 'FS'		, 1)
			  ,(4, 'FAC'	, 1)
			  ,(5, 'GD'		, 1)
			  ,(5, 'SAG'	, 1)
			  ,(6, 'WE'		, 1)
			  ,(6, 'IBCLC'	, 1)
			  ,(6, 'BBIN'	, 1)
			  ,(6, 'WM'		, 1)
			  ,(6, 'ION'	, 1)
			  ,(6, 'BGG'	, 1)
			  ,(6, 'PPL'	, 1)
			  ,(6, 'YB'		, 1)
			  ,(6, 'ON'		, 1)
			  ,(6, 'GPILC'	, 1)
			  ,(6, 'CS'		, 1)
			  ,(6, 'VB'		, 1)
			  ,(6, 'JK'		, 1)
			  ,(6, 'MXG'	, 1)
			  ,(6, 'HB'		, 1)
			  ,(6, 'CG'		, 1)
			  ,(6, 'AP'		, 1)
			  ,(6, 'APM'	, 1)
			  ,(6, 'SEA'	, 1)
			  ,(6, 'JIG'	, 1)
			  ,(6, 'UUSL'	, 1)
			  ,(6, 'NS'		, 1)
			  ,(6, 'GPIRNG'	, 1)
			  ,(6, 'PTRNG'	, 1)
			  ,(6, 'KN'		, 1)
			  ,(6, 'LT'		, 1)
			  ,(6, 'TG'		, 1)
			  ,(6, 'FG'		, 1)
			  ,(6, 'SLT'	, 1)
			  ,(6, 'NG'		, 1)
			  ,(6, 'NG2'	, 1)
			  ,(6, 'VRG'	, 1)
			  ,(6, 'FGGL'	, 1)
			  ,(6, 'VS'		, 1)
			  ,(6, 'VS2'	, 1)
			  ,(6, 'LG'		, 1)
			  ,(6, 'VS4'	, 1)
			  ,(6, 'VS5'	, 1)
			  ,(7, 'SBC'	, 2)
) AS t(Template, ProductPrefix, SPtype)

SELECT @KValue = (
	SELECT k.Template 		AS 'Template'
		 , k.ProductPrefix 	AS 'Code'
		 , k.SPtype			AS 'SP'
	FROM @KeySetting k
	FOR JSON PATH
)

DELETE dbo.LA_SystemSettings WITH (ROWLOCK, UPDLOCK) WHERE [Key] = @KeyName

INSERT INTO dbo.LA_SystemSettings ([Key], [Value])
VALUES (@KeyName, @KValue)
GO