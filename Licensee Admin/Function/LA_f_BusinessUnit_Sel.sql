/*<info serverAlias="DBLIC-bodb_Licensee,DBCUST-bodb_Licensee" selecters="wsv_nap" isFunction="1" isNested="1"></info>*/
CREATE FUNCTION [dbo].[LA_f_BusinessUnit_Sel]
(
)
RETURNS TABLE
AS
/*
	Created: 20250624@Eddie
	DB: DBLIC-bodb_Licensee,DBCUST-bodb_Licensee
	Task: Get Business Unit (BU)

	Revisions:
		- 20250624@Eddie: Initialize Function [RedmineID: #231003]
*/

RETURN
	SELECT BUID, BUCode, BUName
	FROM (
		VALUES (901, 'OT', '901OT')
			  ,(902, 'SP', '902SP')
			  ,(903, 'NV', '903NV')
			  ,(905, 'CD', '905CD')
			  ,(906, 'CL', '906CL')
			  ,(908, 'IM', '908IM')
			  ,(909, 'HC', '909HC')
			  ,(910, 'IH', '910IH')
			  ,(911, 'LG', '911LG')
			  ,(913, 'FI', '913FI')
			  ,(914, 'C5', '914C5')
			  ,(915, 'C1', '915C1')
			  ,(916, 'C3', '916C3')
			  ,(917, 'CT', '917CT')
			  ,(918, 'C2', '918C2')
			  ,(919, 'CI', '919CI')
			  ,(920, 'OL', '920OL')
			  ,(921, 'NF', '921NF')
			  ,(922, 'LT', '922LT')
			  ,(923, 'HJ', '923HJ')
			  ,(924, 'AT', '924AT')
			  ,(925, 'NX', '925NX')
			  ,(926, 'AU', '926AU')
			  ,(928, 'ES', '928ES')
			  ,(929, 'OS', '929OS')
			  ,(931, 'PH', '931PH')
			  ,(932, 'RD', '932RD')
			  ,(933, 'SO', '933SO')
			  ,(934, 'SV', '934SV')
			  ,(935, 'MW', '935MW')
			  ,(936, 'SR', '936SR')
			  ,(937, 'EV', '937EV')
			  ,(938, 'SS', '938SS')
			  ,(939, 'SI', '939SI')
			  ,(940, 'RA', '940RA')
	) AS BU_table (BUID, BUCode, BUName)
GO


