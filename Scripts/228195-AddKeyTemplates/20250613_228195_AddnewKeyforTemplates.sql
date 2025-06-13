/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20250613@Eddie
	DB: DBCUST.bodb_licensee
	Task: Add new key on Manage System Settings function [RedmineID: #228195]
*/
USE bodb_licensee
GO

DECLARE @KeyName1 VARCHAR(100) = 'SettlementReport_SB_Templates'
	  , @KValue1  VARCHAR(4000)
	  , @KeyName2 VARCHAR(100) = 'SettlementReport_SP_Templates'
	  , @KValue2  VARCHAR(4000)

DECLARE @KeySetting1 TABLE ( Template TINYINT, ProductPrefix VARCHAR(10))
DECLARE @KeySetting2 TABLE ( Template TINYINT, ProductId TINYINT )

INSERT INTO @KeySetting1 (Template, ProductPrefix)
SELECT t.Template, t.ProductPrefix
FROM (
		VALUES (1, 'SB'		)
			  ,(2, 'BA'		)
			  ,(3, 'AGC'	)
			  ,(3, 'SG'		)
			  ,(3, 'PP'		)
			  ,(4, 'CC'		)
			  ,(4, 'AB'		)
			  ,(4, 'SXG'	)
			  ,(4, 'PGS'	)
			  ,(4, 'MGRNG'	)
			  ,(4, 'L22'	)
			  ,(4, 'FS'		)
			  ,(4, 'FAC'	)
			  ,(5, 'GD'		)
			  ,(5, 'SAG'	)
			  ,(6, 'WE'		)
			  ,(6, 'IBCLC'	)
			  ,(6, 'BBIN'	)
			  ,(6, 'WM'		)
			  ,(6, 'ION'	)
			  ,(6, 'BGG'	)
			  ,(6, 'PPL'	)
			  ,(6, 'YB'		)
			  ,(6, 'ON'		)
			  ,(6, 'GPILC'	)
			  ,(6, 'CS'		)
			  ,(6, 'VB'		)
			  ,(6, 'JK'		)
			  ,(6, 'MXG'	)
			  ,(6, 'HB'		)
			  ,(6, 'CG'		)
			  ,(6, 'AP'		)
			  ,(6, 'APM'	)
			  ,(6, 'SEA'	)
			  ,(6, 'JIG'	)
			  ,(6, 'UUSL'	)
			  ,(6, 'NS'		)
			  ,(6, 'GPIRNG'	)
			  ,(6, 'PTRNG'	)
			  ,(6, 'KN'		)
			  ,(6, 'LT'		)
			  ,(6, 'TG'		)
			  ,(6, 'FG'		)
			  ,(6, 'SLT'	)
			  ,(6, 'NG'		)
			  ,(6, 'NG2'	)
			  ,(6, 'VRG'	)
			  ,(6, 'FGGL'	)
			  ,(6, 'VS'		)
			  ,(6, 'VS2'	)
			  ,(6, 'LG'		)
			  ,(6, 'VS4'	)
			  ,(6, 'VS5'	)
			  ,(7, 'VGA'	)
			  ,(8, 'SBC'	)
) AS t(Template, ProductPrefix)

SELECT @KValue1 = (
	SELECT k.Template 		AS 'Template'
		 , k.ProductPrefix 	AS 'Code'
	FROM @KeySetting1 k
	FOR JSON PATH
)

INSERT INTO @KeySetting2 (Template, ProductId)
SELECT 1 AS Template, t.ProductId
FROM (
		VALUES (1, 46)
			  ,(1, 60)
			  ,(1, 78)
			  ,(2, 79)
			  ,(2, 87)
			  ,(3, 0 )
) AS t(Template, ProductId)

SELECT @KValue2 = (
	SELECT k.Template  AS 'Template'
		 , k.ProductId AS 'Id'
	FROM @KeySetting2 k
	FOR JSON PATH
)

DELETE dbo.LA_SystemSettings WITH (ROWLOCK, UPDLOCK) WHERE [Key] IN (@KeyName1, @KeyName2)

INSERT INTO dbo.LA_SystemSettings ([Key], [Value])
VALUES (@KeyName1, @KValue1)
	 , (@KeyName2, @KValue2)
GO